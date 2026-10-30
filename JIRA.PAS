{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/cloud-0)
  @website(https://www.gladir.com/vie)
  @abstract(Target: Free Pascal 3.x)

  JIRA : clone de la commande jira (jira-cli, https://github.com/ankitpokhrel/jira-cli).

  Syntaxe generale :
   jira <commande> <sous-commande> [parametres]

  Exemples :
   jira init | jira me | jira open PROJ-123
   jira issue list -tBug -sOpen --plain
   jira issue view PROJ-123 | jira issue assign PROJ-123 "Jean Tremblay"
   jira issue create -tBug -s"Erreur de compilation" -yHigh -b"Le compilateur plante" --no-input
   jira issue move PROJ-123 "In Progress" | jira issue comment add PROJ-123 "Corrige"
   jira sprint list --current | jira sprint add 42 PROJ-1 PROJ-2 | jira project list

  Commandes prises en charge (chacune accepte --help, ex. : jira issue list --help) :
   init                    configure la connexion a Jira
   me                      affiche l'utilisateur connecte
   open [CLE]              ouvre Jira (projet ou ticket) dans le navigateur
   issue list              liste les tickets (filtres -t -s -y -a -r -l -C -P -R -q ...)
   issue view              affiche un ticket (--comments N)
   issue create            cree un ticket (mode interactif ou --no-input)
   issue edit              modifie un ticket
   issue move              change l'etat d'un ticket (transition)
   issue assign            assigne un ticket (x = personne, default = defaut)
   issue comment add       ajoute un commentaire
   issue delete            supprime un ticket (--cascade)
   issue link / unlink     lie ou delie deux tickets ; issue link remote
   issue clone             duplique un ticket
   issue worklog add       enregistre du temps passe
   epic list/create/add/remove
   sprint list/add/close
   release list            versions du projet
   project list            projets
   board list              tableaux Agile
   serverinfo, completion, man, version

  Options generales : -c/--config FICHIER, -p/--project CLE, --debug, --help, --version.
  Options de sortie des listes : --plain, --raw (JSON), --csv, --no-headers,
  --columns, --delimiter, --paginate DEBUT:LIMITE.

  Fonctionnement :
   - configuration : ~/.config/.jira/.config.yml (ou -c, JIRA_CONFIG_FILE) : serveur,
     identifiant, type d'installation (Cloud ou Local), projet, tableau.
   - jeton : variable JIRA_API_TOKEN (sinon ~/.netrc), envoye en Basic
     (identifiant:jeton) ou en Bearer (JIRA_AUTH_TYPE=bearer ou auth_type: bearer).
   - API REST v2 de Jira (et Agile 1.0 pour les sprints, tableaux et epics).
   - Windows : appels reseau par WinInet (wininet.dll) ; autres systemes : curl.
     Sous DOS, les appels reseau ne sont pas disponibles.
   - sortie : sans option, les listes sont affichees en tableau aligne ; --plain
     separe les colonnes par des tabulations.
   - langue de l'aide : francais par defaut, anglais avec LANGUAGE=EN.
}

Program JIRA;

{$IFDEF FPC}
 {$MODE OBJFPC}
 {$H+}
 {$INLINE ON}
 {$R-}
 {$Q-}
 {$IOCHECKS OFF}
 {$NOTES OFF}
 {$HINTS OFF}
 {$WARNINGS OFF}
{$ENDIF}

Uses DOS;

Const
 ToolVersion  = '1.5.1';
 UserAgent    = 'jira-cli pascal/1.5.1';
 {$IFDEF WINDOWS}
 DS = '\';
 {$ELSE}
 DS = '/';
 {$ENDIF}

Type
 TStrArr = Array of AnsiString;

 TSList = Record
  A:TStrArr;
  N:LongInt;
 End;

 TBuf = Record
  D:AnsiString;
  N:LongInt;
 End;

{ ------------------------------------------------------------------ }
{ Utilitaires generaux                                                }
{ ------------------------------------------------------------------ }

Function IStr(N:Int64):AnsiString;
Var
 S:AnsiString;
Begin
 Str(N,S);
 IStr:=S;
End;

Function Fix1(X:Double):AnsiString;
Var
 S:AnsiString;
Begin
 Str(X:0:1,S);
 Fix1:=S;
End;

Function ToInt(Const S:AnsiString;Def:Int64):Int64;
Var
 V:Int64;
 Code:LongInt;
Begin
 Val(S,V,Code);
 If(Code<>0)or(S='')Then ToInt:=Def Else ToInt:=V;
End;

Function LoStr(Const S:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 Result:=S;
 For I:=1 to Length(Result)do If Result[I]in['A'..'Z']Then
   Result[I]:=Chr(Ord(Result[I])+32);
End;

Function UpStr(Const S:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 Result:=S;
 For I:=1 to Length(Result)do If Result[I]in['a'..'z']Then
   Result[I]:=Chr(Ord(Result[I])-32);
End;

Function TrimStr(Const S:AnsiString):AnsiString;
Var
 A,B:LongInt;
Begin
 A:=1;B:=Length(S);
 While(A<=B)and(S[A]in[#0..#32])do Inc(A);
 While(B>=A)and(S[B]in[#0..#32])do Dec(B);
 TrimStr:=Copy(S,A,B-A+1);
End;

Function StartsWith(Const S,P:AnsiString):Boolean;
Begin
 StartsWith:=(Length(S)>=Length(P))and(Copy(S,1,Length(P))=P);
End;

Function EndsWith(Const S,P:AnsiString):Boolean;
Begin
 EndsWith:=(Length(S)>=Length(P))and(Copy(S,Length(S)-Length(P)+1,Length(P))=P);
End;

Function ReplaceAll(Const S,From,Dest:AnsiString):AnsiString;
Var
 P:LongInt;
 T,R:AnsiString;
Begin
 If From='' Then Begin ReplaceAll:=S;Exit;End;
 T:=S;R:='';
 Repeat
  P:=Pos(From,T);
  If P=0 Then Break;
  R:=R+Copy(T,1,P-1)+Dest;
  Delete(T,1,P+Length(From)-1);
 Until False;
 ReplaceAll:=R+T;
End;

Procedure SAdd(Var L:TSList;Const S:AnsiString);
Begin
 If L.N>=Length(L.A)Then SetLength(L.A,Length(L.A)*2+16);
 L.A[L.N]:=S;
 Inc(L.N);
End;

Procedure SClear(Var L:TSList);
Begin
 SetLength(L.A,0);
 L.N:=0;
End;

Function SIndex(Const L:TSList;Const S:AnsiString):LongInt;
Var
 I:LongInt;
Begin
 For I:=0 to L.N-1 do If L.A[I]=S Then Begin SIndex:=I;Exit;End;
 SIndex:=-1;
End;

Procedure SortRange(Var A:TStrArr;Lo,Hi:LongInt);
Var
 I,J:LongInt;
 P,T:AnsiString;
Begin
 While Lo<Hi do Begin
  I:=Lo;J:=Hi;
  P:=A[(Lo+Hi)div 2];
  Repeat
   While A[I]<P do Inc(I);
   While A[J]>P do Dec(J);
   If I<=J Then Begin
    T:=A[I];A[I]:=A[J];A[J]:=T;
    Inc(I);Dec(J);
   End;
  Until I>J;
  If J-Lo<Hi-I Then Begin
   SortRange(A,Lo,J);Lo:=I;
  End
  Else Begin
   SortRange(A,I,Hi);Hi:=J;
  End;
 End;
End;

Procedure SSort(Var L:TSList);
Begin
 If L.N>1 Then SortRange(L.A,0,L.N-1);
End;

{ decoupe S selon le caractere Sep }
Procedure SplitStr(Const S:AnsiString;Sep:Char;Var L:TSList);
Var
 I,B:LongInt;
Begin
 SClear(L);
 B:=1;
 For I:=1 to Length(S)do If S[I]=Sep Then Begin
  SAdd(L,Copy(S,B,I-B));
  B:=I+1;
 End;
 SAdd(L,Copy(S,B,Length(S)-B+1));
End;

Procedure BufAdd(Var B:TBuf;Const S:AnsiString);
Var
 Need:LongInt;
Begin
 If S='' Then Exit;
 Need:=B.N+Length(S);
 If Need>Length(B.D)Then Begin
  If Length(B.D)*2>Need Then SetLength(B.D,Length(B.D)*2)
                        Else SetLength(B.D,Need+4096);
 End;
 Move(S[1],B.D[B.N+1],Length(S));
 B.N:=Need;
End;

Function BufStr(Var B:TBuf):AnsiString;
Begin
 BufStr:=Copy(B.D,1,B.N);
End;

Procedure BufClear(Var B:TBuf);
Begin
 B.D:='';B.N:=0;
End;

{ ------------------------------------------------------------------ }
{ Messages du programme en CP437 (#130, #138, ...) ; la console est en   }
{ UTF-8 : chaque Write/WriteLn est converti a la volee. Les sequences    }
{ UTF-8 valides (noms, textes recus du serveur) passent telles quelles ;  }
{ les octets isoles >= $80 sont des caracteres CP437.                      }
{ ------------------------------------------------------------------ }

Const
 Cp437Tab:Array[128..255]of Word=(
  $00C7,$00FC,$00E9,$00E2,$00E4,$00E0,$00E5,$00E7,
  $00EA,$00EB,$00E8,$00EF,$00EE,$00EC,$00C4,$00C5,
  $00C9,$00E6,$00C6,$00F4,$00F6,$00F2,$00FB,$00F9,
  $00FF,$00D6,$00DC,$00A2,$00A3,$00A5,$20A7,$0192,
  $00E1,$00ED,$00F3,$00FA,$00F1,$00D1,$00AA,$00BA,
  $00BF,$2310,$00AC,$00BD,$00BC,$00A1,$00AB,$00BB,
  $2591,$2592,$2593,$2502,$2524,$2561,$2562,$2556,
  $2555,$2563,$2551,$2557,$255D,$255C,$255B,$2510,
  $2514,$2534,$252C,$251C,$2500,$253C,$255E,$255F,
  $255A,$2554,$2569,$2566,$2560,$2550,$256C,$2567,
  $2568,$2564,$2565,$2559,$2558,$2552,$2553,$256B,
  $256A,$2518,$250C,$2588,$2584,$258C,$2590,$2580,
  $03B1,$00DF,$0393,$03C0,$03A3,$03C3,$00B5,$03C4,
  $03A6,$0398,$03A9,$03B4,$221E,$03C6,$03B5,$2229,
  $2261,$00B1,$2265,$2264,$2320,$2321,$00F7,$2248,
  $00B0,$2219,$00B7,$221A,$207F,$00B2,$25A0,$00A0
 );

Type
 TTextFn=Function(Var F:TextRec):LongInt;

Var
 OrigOutFn,OrigErrFn:TTextFn;
 PendOut,PendErr:AnsiString;

Procedure PutCp437(Var R:AnsiString;Var J:LongInt;B:LongInt);
Var
 W:LongInt;
Begin
 W:=Cp437Tab[B];
 If W<$800 Then Begin
  Inc(J);R[J]:=Chr($C0 or(W shr 6));
  Inc(J);R[J]:=Chr($80 or(W and $3F));
 End
  Else Begin
   Inc(J);R[J]:=Chr($E0 or(W shr 12));
   Inc(J);R[J]:=Chr($80 or((W shr 6)and $3F));
   Inc(J);R[J]:=Chr($80 or(W and $3F));
  End;
End;

Function Cp437ToUtf8(Var Pend:AnsiString;Const Src:AnsiString):AnsiString;
Var
 S,R:AnsiString;
 I,J,N,C,Need,K:LongInt;
 Ok:Boolean;
Begin
 S:=Pend+Src;Pend:='';
 N:=Length(S);
 SetLength(R,N*3);
 I:=1;J:=0;
 While I<=N do Begin
  C:=Ord(S[I]);
  If C<$80 Then Begin Inc(J);R[J]:=S[I];Inc(I);Continue;End;
  Need:=0;
  If(C>=$C2)and(C<=$DF)Then Need:=1
   Else If(C>=$E0)and(C<=$EF)Then Need:=2
   Else If(C>=$F0)and(C<=$F4)Then Need:=3;
  If Need=0 Then Begin PutCp437(R,J,C);Inc(I);Continue;End;
  Ok:=True;
  For K:=1 to Need do Begin
   If I+K>N Then Break;
   If(Ord(S[I+K])and $C0)<>$80 Then Begin Ok:=False;Break;End;
  End;
  If not Ok Then Begin PutCp437(R,J,C);Inc(I);Continue;End;
  If I+Need>N Then Begin Pend:=Copy(S,I,N-I+1);Break;End;
  For K:=0 to Need do Begin Inc(J);R[J]:=S[I+K];End;
  Inc(I,Need+1);
 End;
 SetLength(R,J);
 Cp437ToUtf8:=R;
End;

Function ConvOutput(Var F:TextRec;Orig:TTextFn;Var Pend:AnsiString):LongInt;
Var
 Raw,Conv:AnsiString;
 P,L:LongInt;
Begin
 ConvOutput:=0;
 SetLength(Raw,F.BufPos);
 If F.BufPos>0 Then Move(F.BufPtr^,Raw[1],F.BufPos);
 Conv:=Cp437ToUtf8(Pend,Raw);
 If Conv='' Then Begin F.BufPos:=0;Exit;End;
 P:=1;
 While P<=Length(Conv)do Begin
  L:=Length(Conv)-P+1;
  If L>F.BufSize Then L:=F.BufSize;
  Move(Conv[P],F.BufPtr^,L);
  F.BufPos:=L;
  ConvOutput:=Orig(F);
  Inc(P,L);
 End;
End;

Function OutFn(Var F:TextRec):LongInt;
Begin
 OutFn:=ConvOutput(F,OrigOutFn,PendOut);
End;

Function ErrFn(Var F:TextRec):LongInt;
Begin
 ErrFn:=ConvOutput(F,OrigErrFn,PendErr);
End;

Procedure InstallUtf8Output;
Begin
 SetTextCodePage(Output,DefaultSystemCodePage);
 SetTextCodePage(StdErr,DefaultSystemCodePage);
 OrigOutFn:=TTextFn(TextRec(Output).InOutFunc);
 TextRec(Output).InOutFunc:=@OutFn;
 TextRec(Output).FlushFunc:=@OutFn;
 OrigErrFn:=TTextFn(TextRec(StdErr).InOutFunc);
 TextRec(StdErr).InOutFunc:=@ErrFn;
 TextRec(StdErr).FlushFunc:=@ErrFn;
End;

Procedure Die(Const Msg:AnsiString);
Begin
 WriteLn(StdErr,Msg);
 Halt(1);
End;

Procedure Warn(Const Msg:AnsiString);
Begin
 WriteLn(StdErr,'warning: '+Msg);
End;

{ ------------------------------------------------------------------ }
{ Fichiers et repertoires                                             }
{ ------------------------------------------------------------------ }

Function NormSep(Const S:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 Result:=S;
 For I:=1 to Length(Result)do If Result[I]in['/','\']Then Result[I]:=DS;
End;

Function UnixSep(Const S:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 Result:=S;
 For I:=1 to Length(Result)do If Result[I]='\' Then Result[I]:='/';
End;

Function DropSlash(Const S:AnsiString):AnsiString;
Begin
 Result:=S;
 While(Length(Result)>1)and(Result[Length(Result)]in['/','\'])and
  not((Length(Result)=3)and(Result[2]=':'))do Delete(Result,Length(Result),1);
End;

Function JoinPath(Const A,B:AnsiString):AnsiString;
Begin
 If A='' Then JoinPath:=B Else If B='' Then JoinPath:=A
  Else If A[Length(A)]in['/','\']Then JoinPath:=A+B
  Else JoinPath:=A+DS+B;
End;

Function BaseName(Const S:AnsiString):AnsiString;
Var
 I:LongInt;
 T:AnsiString;
Begin
 T:=DropSlash(S);
 I:=Length(T);
 While(I>0)and not(T[I]in['/','\'])do Dec(I);
 BaseName:=Copy(T,I+1,Length(T)-I);
End;

Function ParentDir(Const S:AnsiString):AnsiString;
Var
 I:LongInt;
 T:AnsiString;
Begin
 T:=DropSlash(S);
 I:=Length(T);
 While(I>0)and not(T[I]in['/','\'])do Dec(I);
 If I<=0 Then ParentDir:='' Else If I=1 Then ParentDir:=Copy(T,1,1)
  Else ParentDir:=Copy(T,1,I-1);
End;

Function PathExists(Const P:AnsiString;Var IsDir:Boolean):Boolean;
Var
 SR:SearchRec;
 T:AnsiString;
Begin
 PathExists:=False;IsDir:=False;
 T:=DropSlash(P);
 If T='' Then Exit;
 FindFirst(T,AnyFile,SR);
 If DosError=0 Then Begin
  PathExists:=True;
  IsDir:=(SR.Attr and Directory)<>0;
 End;
 FindClose(SR);
End;

Function FileExists_(Const P:AnsiString):Boolean;
Var
 D:Boolean;
Begin
 FileExists_:=PathExists(P,D)and not D;
End;

Function DirExists_(Const P:AnsiString):Boolean;
Var
 D:Boolean;
Begin
 DirExists_:=PathExists(P,D)and D;
End;

Procedure MkDirs(Const Path:AnsiString);
Var
 I:LongInt;
 T:AnsiString;
Begin
 T:=DropSlash(Path);
 If(T='')or DirExists_(T)Then Exit;
 For I:=2 to Length(T)do If T[I]in['/','\']Then Begin
  {$I-}MkDir(Copy(T,1,I-1));{$I+}
  If IOResult<>0 Then;
 End;
 {$I-}MkDir(T);{$I+}
 If IOResult<>0 Then;
End;

Function FileSizeOf(Const P:AnsiString):Int64;
Var
 F:File;
Begin
 FileSizeOf:=-1;
 Assign(F,P);
 {$I-}Reset(F,1);{$I+}
 If IOResult<>0 Then Exit;
 FileSizeOf:=FileSize(F);
 Close(F);
 If IOResult<>0 Then;
End;

Function DelFile(Const P:AnsiString):Boolean;
Var
 F:File;
Begin
 Assign(F,P);
 {$I-}Erase(F);{$I+}
 DelFile:=IOResult=0;
End;

Function MoveFile_(Const A,B:AnsiString):Boolean;
Var
 F:File;
Begin
 If FileExists_(B)Then DelFile(B);
 Assign(F,A);
 {$I-}Rename(F,B);{$I+}
 MoveFile_:=IOResult=0;
End;

Function ReadAll(Const P:AnsiString;Var S:AnsiString):Boolean;
Var
 F:File;
 N:Int64;
Begin
 ReadAll:=False;
 S:='';
 Assign(F,P);
 {$I-}Reset(F,1);{$I+}
 If IOResult<>0 Then Exit;
 N:=FileSize(F);
 SetLength(S,N);
 If N>0 Then BlockRead(F,S[1],N);
 Close(F);
 If IOResult<>0 Then Exit;
 ReadAll:=True;
End;

Function WriteAll(Const P,S:AnsiString):Boolean;
Var
 F:File;
Begin
 WriteAll:=False;
 MkDirs(ParentDir(P));
 Assign(F,P);
 {$I-}Rewrite(F,1);{$I+}
 If IOResult<>0 Then Exit;
 If Length(S)>0 Then BlockWrite(F,S[1],Length(S));
 Close(F);
 WriteAll:=IOResult=0;
End;

Function CopyFile_(Const A,B:AnsiString):Boolean;
Var
 F,G:File;
 Buf:Pointer;
 N,W:LongInt;
Begin
 CopyFile_:=False;
 Assign(F,A);
 {$I-}Reset(F,1);{$I+}
 If IOResult<>0 Then Exit;
 MkDirs(ParentDir(B));
 Assign(G,B);
 {$I-}Rewrite(G,1);{$I+}
 If IOResult<>0 Then Begin Close(F);Exit;End;
 GetMem(Buf,262144);
 Repeat
  N:=0;
  {$I-}BlockRead(F,Buf^,262144,N);{$I+}
  If IOResult<>0 Then Break;
  If N>0 Then Begin
   W:=0;
   {$I-}BlockWrite(G,Buf^,N,W);{$I+}
   If(IOResult<>0)or(W<>N)Then Begin N:=-1;Break;End;
  End;
 Until N=0;
 FreeMem(Buf);
 Close(F);Close(G);
 If IOResult<>0 Then;
 CopyFile_:=N=0;
End;

Type
 TEntry = Record
  Name:AnsiString;
  IsDir:Boolean;
 End;
 TEntries = Array of TEntry;

Procedure ListDir(Const Dir:AnsiString;Var E:TEntries);
Var
 SR:SearchRec;
 N:LongInt;
Begin
 SetLength(E,0);N:=0;
 FindFirst(JoinPath(DropSlash(Dir),'*'),AnyFile,SR);
 While DosError=0 do Begin
  If(SR.Name<>'.')and(SR.Name<>'..')Then Begin
   If N>=Length(E)Then SetLength(E,Length(E)*2+16);
   E[N].Name:=SR.Name;
   E[N].IsDir:=(SR.Attr and Directory)<>0;
   Inc(N);
  End;
  FindNext(SR);
 End;
 FindClose(SR);
 SetLength(E,N);
End;

Procedure WalkRec(Const Root,Rel:AnsiString;Var L:TSList);
Var
 E:TEntries;
 I:LongInt;
 R:AnsiString;
Begin
 ListDir(JoinPath(Root,NormSep(Rel)),E);
 For I:=0 to High(E)do Begin
  If Rel='' Then R:=E[I].Name Else R:=Rel+'/'+E[I].Name;
  If E[I].IsDir Then WalkRec(Root,R,L) Else SAdd(L,R);
 End;
End;

{ liste recursive des fichiers : chemins relatifs avec '/' (la liste est videe) }
Procedure WalkFiles(Const Root,Rel:AnsiString;Var L:TSList);
Begin
 SClear(L);
 WalkRec(Root,Rel,L);
End;

Procedure RmTree(Const Dir:AnsiString);
Var
 E:TEntries;
 I:LongInt;
 P:AnsiString;
Begin
 ListDir(Dir,E);
 For I:=0 to High(E)do Begin
  P:=JoinPath(Dir,E[I].Name);
  If E[I].IsDir Then RmTree(P) Else DelFile(P);
 End;
 {$I-}RmDir(DropSlash(Dir));{$I+}
 If IOResult<>0 Then;
End;

Function AbsPath(Const P:AnsiString):AnsiString;
Begin
 AbsPath:=DropSlash(FExpand(P));
End;

Function HomeDir:AnsiString;
Begin
 Result:=GetEnv('HOME');
 If Result='' Then Result:=GetEnv('USERPROFILE');
 If Result='' Then Result:='.';
End;

{ ------------------------------------------------------------------ }
{ Dates                                                               }
{ ------------------------------------------------------------------ }

Function DaysFromCivil(Y0,M,D:LongInt):Int64;
Var
 Y,Era,Yoe,Doy,Doe:Int64;
Begin
 Y:=Y0;
 If M<=2 Then Dec(Y);
 If Y>=0 Then Era:=Y div 400 Else Era:=(Y-399)div 400;
 Yoe:=Y-Era*400;
 If M>2 Then Doy:=(153*(M-3)+2)div 5+D-1 Else Doy:=(153*(M+9)+2)div 5+D-1;
 Doe:=Yoe*365+Yoe div 4-Yoe div 100+Doy;
 DaysFromCivil:=Era*146097+Doe-719468;
End;

Function NowEpoch:Int64;
Var
 Y,M,D,DW,H,Mi,S,HS:Word;
Begin
 GetDate(Y,M,D,DW);
 GetTime(H,Mi,S,HS);
 NowEpoch:=DaysFromCivil(Y,M,D)*86400+H*3600+Mi*60+S;
End;

Function PackedEpoch(T:LongInt):Int64;
Var
 DT:DateTime;
Begin
 UnpackTime(T,DT);
 PackedEpoch:=DaysFromCivil(DT.Year,DT.Month,DT.Day)*86400+DT.Hour*3600+DT.Min*60+DT.Sec;
End;

Function FileMTime(Const P:AnsiString):Int64;
Var
 F:File;
 T:LongInt;
Begin
 FileMTime:=0;
 Assign(F,P);
 {$I-}Reset(F,1);{$I+}
 If IOResult<>0 Then Exit;
 GetFTime(F,T);
 If DosError=0 Then FileMTime:=PackedEpoch(T);
 Close(F);
 If IOResult<>0 Then;
End;

Function StampToStr(E:Int64):AnsiString;
Var
 Days,Rem_:Int64;
 Z,Era,Doe,Yoe,Y,Doy,Mp,D,M:Int64;
 S:AnsiString;
 Function P2(N:Int64):AnsiString;
 Begin
  If N<10 Then P2:='0'+IStr(N) Else P2:=IStr(N);
 End;
Begin
 Days:=E div 86400;Rem_:=E mod 86400;
 Z:=Days+719468;
 If Z>=0 Then Era:=Z div 146097 Else Era:=(Z-146096)div 146097;
 Doe:=Z-Era*146097;
 Yoe:=(Doe-Doe div 1460+Doe div 36524-Doe div 146096)div 365;
 Y:=Yoe+Era*400;
 Doy:=Doe-(365*Yoe+Yoe div 4-Yoe div 100);
 Mp:=(5*Doy+2)div 153;
 D:=Doy-(153*Mp+2)div 5+1;
 If Mp<10 Then M:=Mp+3 Else M:=Mp-9;
 If M<=2 Then Inc(Y);
 S:=IStr(Y)+'-'+P2(M)+'-'+P2(D)+' '+P2(Rem_ div 3600)+':'+P2((Rem_ mod 3600)div 60)+
   ':'+P2(Rem_ mod 60);
 StampToStr:=S;
End;

Function AgoStr(Secs:Int64):AnsiString;
Var
 N:Int64;
 Function Pl(N:Int64;Const U:AnsiString):AnsiString;
 Begin
  If N=1 Then Pl:='1 '+U+' ago' Else Pl:=IStr(N)+' '+U+'s ago';
 End;
Begin
 If Secs<0 Then Secs:=0;
 If Secs<60 Then AgoStr:='a few seconds ago'
 Else If Secs<3600 Then AgoStr:=Pl(Secs div 60,'minute')
 Else If Secs<86400 Then AgoStr:=Pl(Secs div 3600,'hour')
 Else If Secs<86400*30 Then AgoStr:=Pl(Secs div 86400,'day')
 Else If Secs<86400*365 Then AgoStr:=Pl(Secs div(86400*30),'month')
 Else AgoStr:=Pl(Secs div(86400*365),'year');
End;

Procedure WaitSec(N:LongInt);
Var
 Y,M,D,DW:Word;
 H,Mi,S,HS:Word;
 T0,T1:Int64;
Begin
 T0:=NowEpoch;
 Repeat
  T1:=NowEpoch;
 Until T1-T0>=N;
End;

Function HumanSize(N:Int64):AnsiString;
Const
 Units:Array[0..4]of AnsiString=('B','K','M','G','T');
Var
 D:Double;
 U:LongInt;
Begin
 D:=N;U:=0;
 While(D>=1000)and(U<4)do Begin D:=D/1000;Inc(U);End;
 If U=0 Then HumanSize:=IStr(N)+'B' Else HumanSize:=Fix1(D)+Units[U];
End;

{ ------------------------------------------------------------------ }
{ Globs (fnmatch) et URL                                              }
{ ------------------------------------------------------------------ }

Function GlobMatch(Const P:AnsiString;PI:LongInt;Const S:AnsiString;SI:LongInt):Boolean;
Var
 C:Char;
 J:LongInt;
 Neg,Ok:Boolean;
Begin
 GlobMatch:=False;
 While PI<=Length(P)do Begin
  C:=P[PI];
  If C='*' Then Begin
   While(PI<=Length(P))and(P[PI]='*')do Inc(PI);
   If PI>Length(P)Then Begin GlobMatch:=True;Exit;End;
   While SI<=Length(S)+1 do Begin
    If GlobMatch(P,PI,S,SI)Then Begin GlobMatch:=True;Exit;End;
    Inc(SI);
   End;
   Exit;
  End
  Else If C='?' Then Begin
   If SI>Length(S)Then Exit;
   Inc(PI);Inc(SI);
  End
  Else If C='[' Then Begin
   J:=PI+1;
   Neg:=False;
   If(J<=Length(P))and(P[J]in['!','^'])Then Begin Neg:=True;Inc(J);End;
   Ok:=False;
   If SI>Length(S)Then Exit;
   Repeat
    If J>Length(P)Then Break;
    If(P[J]=']')and(J>PI+1+Ord(Neg))Then Break;
    If(J+2<=Length(P))and(P[J+1]='-')and(P[J+2]<>']')Then Begin
     If(S[SI]>=P[J])and(S[SI]<=P[J+2])Then Ok:=True;
     Inc(J,3);
    End
    Else Begin
     If S[SI]=P[J]Then Ok:=True;
     Inc(J);
    End;
   Until False;
   If J>Length(P)Then Begin
    { crochet non ferme : caractere litteral }
    If S[SI]<>'[' Then Exit;
    Inc(PI);Inc(SI);
   End
   Else Begin
    If Ok=Neg Then Exit;
    PI:=J+1;Inc(SI);
   End;
  End
  Else Begin
   If(SI>Length(S))or(S[SI]<>C)Then Exit;
   Inc(PI);Inc(SI);
  End;
 End;
 GlobMatch:=SI>Length(S);
End;

Function Glob(Const Pat,S:AnsiString):Boolean;
Var
 P:AnsiString;
Begin
 P:=Pat;
 If EndsWith(P,'/')Then P:=P+'*';
 Glob:=GlobMatch(P,1,S,1);
End;

Function HasWild(Const S:AnsiString):Boolean;
Begin
 HasWild:=(Pos('*',S)>0)or(Pos('?',S)>0)or(Pos('[',S)>0);
End;

Function UrlEnc(Const S:AnsiString;KeepSlash:Boolean):AnsiString;
Const
 Hex:AnsiString='0123456789ABCDEF';
Var
 I:LongInt;
 C:Char;
Begin
 Result:='';
 For I:=1 to Length(S)do Begin
  C:=S[I];
  If C in['A'..'Z','a'..'z','0'..'9','-','_','.','~']Then Result:=Result+C
  Else If(C='/')and KeepSlash Then Result:=Result+C
  Else Result:=Result+'%'+Hex[(Ord(C)shr 4)+1]+Hex[(Ord(C)and 15)+1];
 End;
End;

Function UrlQ(Const S:AnsiString):AnsiString;
Begin
 UrlQ:=UrlEnc(S,False);
End;

Procedure SplitUrl(Const U:AnsiString;Var Scheme,Host:AnsiString;Var Port:LongInt;Var
  Path:AnsiString);
Var
 P,Q:LongInt;
 HP:AnsiString;
Begin
 Scheme:='http';Port:=0;Path:='/';
 P:=Pos('://',U);
 If P>0 Then Begin
  Scheme:=LoStr(Copy(U,1,P-1));
  HP:=Copy(U,P+3,Length(U));
 End
 Else HP:=U;
 Q:=Pos('/',HP);
 If Q>0 Then Begin
  Path:=Copy(HP,Q,Length(HP));
  HP:=Copy(HP,1,Q-1);
 End;
 Q:=Pos('@',HP);
 If Q>0 Then Delete(HP,1,Q);
 Q:=Pos(':',HP);
 If Q>0 Then Begin
  Port:=ToInt(Copy(HP,Q+1,Length(HP)),0);
  HP:=Copy(HP,1,Q-1);
 End;
 If Port=0 Then If Scheme='https' Then Port:=443 Else Port:=80;
 Host:=HP;
End;

Function UrlHost(Const U:AnsiString):AnsiString;
Var
 Sc,H,Pa:AnsiString;
 Po:LongInt;
Begin
 SplitUrl(U,Sc,H,Po,Pa);
 UrlHost:=LoStr(H);
End;

Function ResolveUrl(Const Base,Loc:AnsiString):AnsiString;
Var
 Sc,H,Pa:AnsiString;
 Po,I:LongInt;
 Pre:AnsiString;
Begin
 If(Pos('://',Loc)>0)and(Pos('://',Loc)<8)Then Begin ResolveUrl:=Loc;Exit;End;
 SplitUrl(Base,Sc,H,Po,Pa);
 Pre:=Sc+'://'+H;
 If((Sc='https')and(Po<>443))or((Sc='http')and(Po<>80))Then Pre:=Pre+':'+IStr(Po);
 If StartsWith(Loc,'/')Then ResolveUrl:=Pre+Loc
 Else Begin
  I:=Length(Pa);
  While(I>0)and(Pa[I]<>'/')do Dec(I);
  ResolveUrl:=Pre+Copy(Pa,1,I)+Loc;
 End;
End;

{ ------------------------------------------------------------------ }
{ JSON                                                                }
{ ------------------------------------------------------------------ }

Const
 JK_NULL=0; JK_BOOL=1; JK_NUM=2; JK_STR=3; JK_ARR=4; JK_OBJ=5;

Type
 TJNode = Record
  Kind:Byte;
  Key,S:AnsiString;
  First,Last,Next,Cnt:LongInt;
 End;

Var
 JP:Array of TJNode;
 JN:LongInt;
 JSrc:AnsiString;
 JPos:LongInt;
 JErr:Boolean;

Function JNew(K:Byte):LongInt;
Begin
 If JN>=Length(JP)Then SetLength(JP,Length(JP)*2+1024);
 JP[JN].Kind:=K;
 JP[JN].Key:='';
 JP[JN].S:='';
 JP[JN].First:=-1;JP[JN].Last:=-1;JP[JN].Next:=-1;JP[JN].Cnt:=0;
 JNew:=JN;
 Inc(JN);
End;

Procedure JAppend(Par,Child:LongInt);
Begin
 If JP[Par].Last<0 Then JP[Par].First:=Child Else JP[JP[Par].Last].Next:=Child;
 JP[Par].Last:=Child;
 Inc(JP[Par].Cnt);
End;

Procedure JReset;
Begin
 SetLength(JP,0);
 JN:=0;
End;

Procedure JSkip;
Begin
 While(JPos<=Length(JSrc))and(JSrc[JPos]in[#9,#10,#13,' '])do Inc(JPos);
End;

Function Utf8Enc(C:LongWord):AnsiString;
Begin
 If C<$80 Then Utf8Enc:=Chr(C)
 Else If C<$800 Then Utf8Enc:=Chr($C0 or(C shr 6))+Chr($80 or(C and $3F))
 Else If C<$10000 Then Utf8Enc:=Chr($E0 or(C shr 12))+Chr($80 or((C shr 6)and $3F))+
   Chr($80 or(C and $3F))
 Else Utf8Enc:=Chr($F0 or(C shr 18))+Chr($80 or((C shr 12)and $3F))+
   Chr($80 or((C shr 6)and $3F))+Chr($80 or(C and $3F));
End;

Function HexVal(Const S:AnsiString;P:LongInt):LongInt;
Var
 I:LongInt;
 C:Char;
Begin
 Result:=0;
 For I:=P to P+3 do Begin
  If I>Length(S)Then Begin JErr:=True;Exit;End;
  C:=S[I];
  If C in['0'..'9']Then Result:=Result*16+Ord(C)-48
  Else If C in['a'..'f']Then Result:=Result*16+Ord(C)-87
  Else If C in['A'..'F']Then Result:=Result*16+Ord(C)-55
  Else Begin JErr:=True;Exit;End;
 End;
End;

Function JStrLit:AnsiString;
Var
 B:TBuf;
 C:Char;
 U,U2:LongInt;
 Run:LongInt;
Begin
 BufClear(B);
 Inc(JPos);
 Run:=JPos;
 While True do Begin
  If JPos>Length(JSrc)Then Begin JErr:=True;Break;End;
  C:=JSrc[JPos];
  If(C='"')or(C='\')Then Begin
   If JPos>Run Then BufAdd(B,Copy(JSrc,Run,JPos-Run));
   If C='"' Then Begin Inc(JPos);Break;End;
   Inc(JPos);
   If JPos>Length(JSrc)Then Begin JErr:=True;Break;End;
   C:=JSrc[JPos];
   Case C of
    'n':BufAdd(B,#10);
    't':BufAdd(B,#9);
    'r':BufAdd(B,#13);
    'b':BufAdd(B,#8);
    'f':BufAdd(B,#12);
    'u':Begin
         U:=HexVal(JSrc,JPos+1);
         Inc(JPos,4);
         If(U>=$D800)and(U<$DC00)and(Copy(JSrc,JPos+1,2)='\u')Then Begin
          U2:=HexVal(JSrc,JPos+3);
          If(U2>=$DC00)and(U2<$E000)Then Begin
           U:=$10000+((U-$D800)shl 10)+(U2-$DC00);
           Inc(JPos,6);
          End;
         End;
         BufAdd(B,Utf8Enc(U));
        End;
    Else BufAdd(B,C);
   End;
   Inc(JPos);
   Run:=JPos;
  End
  Else Inc(JPos);
  If JErr Then Break;
 End;
 JStrLit:=BufStr(B);
End;

Function JVal(Depth:LongInt):LongInt;
Var
 C:Char;
 K,Q:LongInt;
 Key:AnsiString;
Begin
 Result:=-1;
 JSkip;
 If(JPos>Length(JSrc))or(Depth>200)Then Begin JErr:=True;Exit;End;
 C:=JSrc[JPos];
 If C='{' Then Begin
  Result:=JNew(JK_OBJ);
  Inc(JPos);JSkip;
  If(JPos<=Length(JSrc))and(JSrc[JPos]='}')Then Begin Inc(JPos);Exit;End;
  Repeat
   JSkip;
   If(JPos>Length(JSrc))or(JSrc[JPos]<>'"')Then Begin JErr:=True;Exit;End;
   Key:=JStrLit;
   If JErr Then Exit;
   JSkip;
   If(JPos>Length(JSrc))or(JSrc[JPos]<>':')Then Begin JErr:=True;Exit;End;
   Inc(JPos);
   K:=JVal(Depth+1);
   If JErr Then Exit;
   JP[K].Key:=Key;
   JAppend(Result,K);
   JSkip;
   If JPos>Length(JSrc)Then Begin JErr:=True;Exit;End;
   If JSrc[JPos]=',' Then Inc(JPos)
   Else If JSrc[JPos]='}' Then Begin Inc(JPos);Exit;End
   Else Begin JErr:=True;Exit;End;
  Until False;
 End
 Else If C='[' Then Begin
  Result:=JNew(JK_ARR);
  Inc(JPos);JSkip;
  If(JPos<=Length(JSrc))and(JSrc[JPos]=']')Then Begin Inc(JPos);Exit;End;
  Repeat
   K:=JVal(Depth+1);
   If JErr Then Exit;
   JAppend(Result,K);
   JSkip;
   If JPos>Length(JSrc)Then Begin JErr:=True;Exit;End;
   If JSrc[JPos]=',' Then Inc(JPos)
   Else If JSrc[JPos]=']' Then Begin Inc(JPos);Exit;End
   Else Begin JErr:=True;Exit;End;
  Until False;
 End
 Else If C='"' Then Begin
  Key:=JStrLit;
  Result:=JNew(JK_STR);
  JP[Result].S:=Key;
 End
 Else If Copy(JSrc,JPos,4)='true' Then Begin
  Result:=JNew(JK_BOOL);JP[Result].S:='true';Inc(JPos,4);
 End
 Else If Copy(JSrc,JPos,5)='false' Then Begin
  Result:=JNew(JK_BOOL);JP[Result].S:='false';Inc(JPos,5);
 End
 Else If Copy(JSrc,JPos,4)='null' Then Begin
  Result:=JNew(JK_NULL);Inc(JPos,4);
 End
 Else If C in['-','0'..'9']Then Begin
  Q:=JPos;
  While(JPos<=Length(JSrc))and(JSrc[JPos]in['-','+','.','e','E','0'..'9'])do Inc(JPos);
  Result:=JNew(JK_NUM);
  JP[Result].S:=Copy(JSrc,Q,JPos-Q);
 End
 Else JErr:=True;
End;

{ analyse S ; renvoie l'indice de la racine ou -1 }
Function JParse(Const S:AnsiString):LongInt;
Begin
 JSrc:=S;JPos:=1;JErr:=False;
 Result:=JVal(0);
 If JErr Then Result:=-1;
End;

Function JGet(O:LongInt;Const Key:AnsiString):LongInt;
Var
 C:LongInt;
Begin
 JGet:=-1;
 If(O<0)or(JP[O].Kind<>JK_OBJ)Then Exit;
 C:=JP[O].First;
 While C>=0 do Begin
  If JP[C].Key=Key Then Begin JGet:=C;Exit;End;
  C:=JP[C].Next;
 End;
End;

{ chemin a points : "a.b.c" }
Function JPath(O:LongInt;Const Path:AnsiString):LongInt;
Var
 L:TSList;
 I:LongInt;
Begin
 SplitStr(Path,'.',L);
 JPath:=O;
 For I:=0 to L.N-1 do Begin
  JPath:=JGet(JPath,L.A[I]);
  If JPath<0 Then Exit;
 End;
End;

Function JAt(A,I:LongInt):LongInt;
Var
 C:LongInt;
Begin
 JAt:=-1;
 If(A<0)or not(JP[A].Kind in[JK_ARR,JK_OBJ])Then Exit;
 C:=JP[A].First;
 While(C>=0)and(I>0)do Begin C:=JP[C].Next;Dec(I);End;
 JAt:=C;
End;

Function JCnt(A:LongInt):LongInt;
Begin
 If A<0 Then JCnt:=0 Else JCnt:=JP[A].Cnt;
End;

Function JTxt(N:LongInt):AnsiString;
Begin
 If N<0 Then JTxt:='' Else If JP[N].Kind in[JK_STR,JK_NUM,JK_BOOL]Then JTxt:=JP[N].S
  Else JTxt:='';
End;

Function JS(O:LongInt;Const Path:AnsiString):AnsiString;
Begin
 JS:=JTxt(JPath(O,Path));
End;

Function JI(O:LongInt;Const Path:AnsiString):Int64;
Var
 N:LongInt;
 D:Double;
 Code:LongInt;
 V:Int64;
Begin
 N:=JPath(O,Path);
 JI:=0;
 If(N<0)or(JP[N].Kind<>JK_NUM)Then Exit;
 Val(JP[N].S,V,Code);
 If Code=0 Then JI:=V
 Else Begin
  Val(JP[N].S,D,Code);
  If Code=0 Then JI:=Trunc(D);
 End;
End;

Function JB(O:LongInt;Const Path:AnsiString):Boolean;
Begin
 JB:=JS(O,Path)='true';
End;

Function JEsc(Const S:AnsiString):AnsiString;
Const
 Hex:AnsiString='0123456789abcdef';
Var
 I:LongInt;
 B:TBuf;
 C:Char;
Begin
 BufClear(B);
 For I:=1 to Length(S)do Begin
  C:=S[I];
  Case C of
   '"':BufAdd(B,'\"');
   '\':BufAdd(B,'\\');
   #10:BufAdd(B,'\n');
   #13:BufAdd(B,'\r');
   #9:BufAdd(B,'\t');
   #0..#8,#11,#12,#14..#31:BufAdd(B,'\u00'+Hex[(Ord(C)shr 4)+1]+Hex[(Ord(C)and 15)+1]);
   Else BufAdd(B,C);
  End;
 End;
 JEsc:=BufStr(B);
End;

Function JQ(Const S:AnsiString):AnsiString;
Begin
 JQ:='"'+JEsc(S)+'"';
End;

Function JBool(B:Boolean):AnsiString;
Begin
 If B Then JBool:='true' Else JBool:='false';
End;

Procedure JDump(N:LongInt;Ind:LongInt;Var B:TBuf);
Var
 C:LongInt;
 Pad:AnsiString;
Begin
 If N<0 Then Begin BufAdd(B,'null');Exit;End;
 Case JP[N].Kind of
  JK_NULL:BufAdd(B,'null');
  JK_BOOL,JK_NUM:BufAdd(B,JP[N].S);
  JK_STR:BufAdd(B,JQ(JP[N].S));
  JK_ARR,JK_OBJ:Begin
   If JP[N].Cnt=0 Then Begin
    If JP[N].Kind=JK_ARR Then BufAdd(B,'[]') Else BufAdd(B,'{}');
    Exit;
   End;
   Pad:=StringOfChar(' ',(Ind+1)*2);
   If JP[N].Kind=JK_ARR Then BufAdd(B,'[') Else BufAdd(B,'{');
   C:=JP[N].First;
   While C>=0 do Begin
    BufAdd(B,#10+Pad);
    If JP[N].Kind=JK_OBJ Then BufAdd(B,JQ(JP[C].Key)+': ');
    JDump(C,Ind+1,B);
    C:=JP[C].Next;
    If C>=0 Then BufAdd(B,',');
   End;
   BufAdd(B,#10+StringOfChar(' ',Ind*2));
   If JP[N].Kind=JK_ARR Then BufAdd(B,']') Else BufAdd(B,'}');
  End;
 End;
End;

Procedure JPrint(N:LongInt);
Var
 B:TBuf;
Begin
 BufClear(B);
 JDump(N,0,B);
 WriteLn(BufStr(B));
End;
Const
 B64:AnsiString='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

Procedure B64Add(Var B:TBuf;Const S:AnsiString);
Var
 I,N:LongInt;
 X:LongWord;
 O:AnsiString;
Begin
 N:=Length(S);
 SetLength(O,((N+2)div 3)*4);
 I:=1;
 N:=0;
 While I+2<=Length(S)do Begin
  X:=(LongWord(Ord(S[I]))shl 16)or(LongWord(Ord(S[I+1]))shl 8)or Ord(S[I+2]);
  O[N+1]:=B64[(X shr 18)+1];O[N+2]:=B64[((X shr 12)and 63)+1];
  O[N+3]:=B64[((X shr 6)and 63)+1];O[N+4]:=B64[(X and 63)+1];
  Inc(N,4);Inc(I,3);
 End;
 If Length(S)-I+1=1 Then Begin
  X:=LongWord(Ord(S[I]))shl 16;
  O[N+1]:=B64[(X shr 18)+1];O[N+2]:=B64[((X shr 12)and 63)+1];
  O[N+3]:='=';O[N+4]:='=';
 End
 Else If Length(S)-I+1=2 Then Begin
  X:=(LongWord(Ord(S[I]))shl 16)or(LongWord(Ord(S[I+1]))shl 8);
  O[N+1]:=B64[(X shr 18)+1];O[N+2]:=B64[((X shr 12)and 63)+1];
  O[N+3]:=B64[((X shr 6)and 63)+1];O[N+4]:='=';
 End;
 BufAdd(B,O);
End;

Function B64Str(Const S:AnsiString):AnsiString;
Var
 B:TBuf;
Begin
 BufClear(B);
 B64Add(B,S);
 B64Str:=BufStr(B);
End;

Function TrimRight_(Const S:AnsiString):AnsiString;
Var
 B:LongInt;
Begin
 B:=Length(S);
 While(B>0)and(S[B]=' ')do Dec(B);
 TrimRight_:=Copy(S,1,B);
End;

Function IfThen_(C:Boolean;Const A,B:AnsiString):AnsiString;
Begin
 If C Then IfThen_:=A Else IfThen_:=B;
End;

{ decodage base64 (les caracteres invalides sont ignores) }
Function B64Dec(Const S:AnsiString):AnsiString;
Var
 I,Bits,Acc:LongInt;
 P:LongInt;
 C:Char;
 B:TBuf;
Begin
 BufClear(B);
 Acc:=0;Bits:=0;
 For I:=1 to Length(S)do Begin
  C:=S[I];
  If C='-' Then C:='+' Else If C='_' Then C:='/';
  If C='=' Then Break;
  P:=Pos(C,B64);
  If P=0 Then Continue;
  Acc:=(Acc shl 6)or(P-1);
  Inc(Bits,6);
  If Bits>=8 Then Begin
   Dec(Bits,8);
   BufAdd(B,Chr((Acc shr Bits)and $FF));
   Acc:=Acc and((1 shl Bits)-1);
  End;
 End;
 B64Dec:=BufStr(B);
End;
{ ------------------------------------------------------------------ }
{ Couche HTTP : WinInet (Windows) ou curl (autres systemes)           }
{ ------------------------------------------------------------------ }

Type
 THttpReq = Record
  Method,Url,Token,Headers:AnsiString;
  BodyStr:AnsiString;
  BodyFile:AnsiString;
  BodyOfs,BodyLen:Int64;
  OutFile:AnsiString;
  ResumeFrom:Int64;
  Follow,StopAtLinked:Boolean;
  ProgLabel:AnsiString;
  ShowProg:Boolean;
  Status:LongInt;
  RespHeaders,RespBody,Err:AnsiString;
  Got,Total:Int64;
 End;

Var
 ProgLast:LongInt;

Procedure ReqInit(Var R:THttpReq;Const Method,Url,Token:AnsiString);
Begin
 R.Method:=Method;R.Url:=Url;R.Token:=Token;R.Headers:='';
 R.BodyStr:='';R.BodyFile:='';R.BodyOfs:=0;R.BodyLen:=0;
 R.OutFile:='';R.ResumeFrom:=0;
 R.Follow:=True;R.StopAtLinked:=False;
 R.ProgLabel:='';R.ShowProg:=False;
 R.Status:=0;R.RespHeaders:='';R.RespBody:='';R.Err:='';
 R.Got:=0;R.Total:=-1;
End;

{ derniere reponse d'un en-tete HTTP (curl ajoute plusieurs blocs) }
Function LastHeaderBlock(Const S:AnsiString):AnsiString;
Var
 I,B:LongInt;
Begin
 B:=1;
 I:=1;
 While I<=Length(S)do Begin
  If(Copy(S,I,5)='HTTP/')and((I=1)or(S[I-1]=#10))Then B:=I;
  Inc(I);
 End;
 LastHeaderBlock:=Copy(S,B,Length(S));
End;

Function HeaderGet(Const H,Name:AnsiString):AnsiString;
Var
 L:TSList;
 I,P:LongInt;
 Ln,Nm:AnsiString;
Begin
 HeaderGet:='';
 Nm:=LoStr(Name)+':';
 SplitStr(ReplaceAll(H,#13,''),#10,L);
 For I:=0 to L.N-1 do Begin
  Ln:=L.A[I];
  If StartsWith(LoStr(Ln),Nm)Then Begin
   P:=Pos(':',Ln);
   HeaderGet:=TrimStr(Copy(Ln,P+1,Length(Ln)));
   Exit;
  End;
 End;
End;

Function StatusFromHeaders(Const H:AnsiString):LongInt;
Var
 P:LongInt;
 T:AnsiString;
Begin
 T:=LastHeaderBlock(H);
 P:=Pos(' ',T);
 If P=0 Then Begin StatusFromHeaders:=0;Exit;End;
 StatusFromHeaders:=ToInt(Copy(T,P+1,3),0);
End;

Function BuildHeaders(Var R:THttpReq):AnsiString;
Begin
 Result:='Accept-Encoding: identity'#13#10'X-Atlassian-Token: no-check'#13#10;
 If Pos('accept:',LoStr(R.Headers))=0 Then Result:=Result+'Accept: application/json'#13#10;
 {$IFNDEF WINDOWS}
 Result:=Result+'User-Agent: '+UserAgent+#13#10;
 {$ENDIF}
 If R.Token<>'' Then Result:=Result+'Authorization: '+R.Token+#13#10;
 Result:=Result+R.Headers;
End;

Procedure ShowProgress(Var R:THttpReq);
Var
 Pc,Bar,I:LongInt;
 S:AnsiString;
Begin
 If not R.ShowProg Then Exit;
 If R.Total>0 Then Begin
  Pc:=(R.Got*100)div R.Total;
  If(Pc=ProgLast)and(R.Got<R.Total)Then Exit;
  ProgLast:=Pc;
  Bar:=Pc div 5;
  S:='';
  For I:=1 to 20 do If I<=Bar Then S:=S+'#' Else S:=S+'.';
  Write(StdErr,#13,R.ProgLabel,' [',S,'] ',Pc:3,'% ',HumanSize(R.Got),'/',
    HumanSize(R.Total),'      ');
 End
 Else Begin
  Pc:=R.Got div 1048576;
  If Pc=ProgLast Then Exit;
  ProgLast:=Pc;
  Write(StdErr,#13,R.ProgLabel,' ',HumanSize(R.Got),'      ');
 End;
End;

Procedure ProgressEnd(Var R:THttpReq);
Begin
 If R.ShowProg and(R.Got>0)Then WriteLn(StdErr);
End;

{$IFDEF WINDOWS}
Type
 TInetBuf = Record
  dwStructSize:LongWord;
  Next:Pointer;
  lpcszHeader:PChar;
  dwHeadersLength,dwHeadersTotal:LongWord;
  lpvBuffer:Pointer;
  dwBufferLength,dwBufferTotal,dwOffsetLow,dwOffsetHigh:LongWord;
 End;

Function InternetOpenA(Agent:PChar;Access:LongWord;Proxy,
  Bypass:PChar;Flags:LongWord):Pointer;
 stdcall;external 'wininet.dll' name 'InternetOpenA';
Function InternetConnectA(H:Pointer;Host:PChar;Port:LongWord;User,
  Pass:PChar;Service,Flags:LongWord;Ctx:PtrUInt):Pointer;
 stdcall;external 'wininet.dll' name 'InternetConnectA';
Function HttpOpenRequestA(H:Pointer;Verb,Obj,Ver,Ref:PChar;Accept:Pointer;
  Flags:LongWord;Ctx:PtrUInt):Pointer;
 stdcall;external 'wininet.dll' name 'HttpOpenRequestA';
Function HttpSendRequestA(H:Pointer;Hdr:PChar;HdrLen:LongWord;Opt:Pointer;
  OptLen:LongWord):LongInt;
 stdcall;external 'wininet.dll' name 'HttpSendRequestA';
Function HttpSendRequestExA(H:Pointer;InBuf,OutBuf:Pointer;Flags:LongWord;
  Ctx:PtrUInt):LongInt;
 stdcall;external 'wininet.dll' name 'HttpSendRequestExA';
Function InternetWriteFile(H:Pointer;Buf:Pointer;N:LongWord;Var Written:LongWord):LongInt;
 stdcall;external 'wininet.dll' name 'InternetWriteFile';
Function HttpEndRequestA(H:Pointer;OutBuf:Pointer;Flags:LongWord;Ctx:PtrUInt):LongInt;
 stdcall;external 'wininet.dll' name 'HttpEndRequestA';
Function InternetReadFile(H:Pointer;Buf:Pointer;ToRead:LongWord;Var
  Got:LongWord):LongInt;
 stdcall;external 'wininet.dll' name 'InternetReadFile';
Function InternetCloseHandle(H:Pointer):LongInt;
 stdcall;external 'wininet.dll' name 'InternetCloseHandle';
Function HttpQueryInfoA(H:Pointer;InfoLevel:LongWord;Buf:Pointer;Var
  BufLen:LongWord;Index:Pointer):LongInt;
 stdcall;external 'wininet.dll' name 'HttpQueryInfoA';
Function InternetSetOptionA(H:Pointer;Opt:LongWord;Buf:Pointer;BufLen:LongWord):LongInt;
 stdcall;external 'wininet.dll' name 'InternetSetOptionA';

Procedure HttpOnce(Var R:THttpReq);
Var
 Sc,Host,Path,Hdr,HB:AnsiString;
 Port:LongInt;
 Sess,Conn,Req:Pointer;
 Flags,Tmo,L,Gt:LongWord;
 IB:TInetBuf;
 Buf:Pointer;
 F,BF:File;
 N,Want:LongInt;
 Left,Ofs:Int64;
 B:TBuf;
 OpenOut,UseEx,Ok:Boolean;
 Cl:AnsiString;
Begin
 R.Status:=0;R.RespHeaders:='';R.RespBody:='';R.Err:='';R.Got:=0;R.Total:=-1;
 SplitUrl(R.Url,Sc,Host,Port,Path);
 Sess:=InternetOpenA(UserAgent,0,Nil,Nil,0);
 If Sess=Nil Then Begin R.Err:='cannot initialize WinInet';Exit;End;
 Tmo:=60000;
 InternetSetOptionA(Sess,2,@Tmo,4);
 InternetSetOptionA(Sess,5,@Tmo,4);
 InternetSetOptionA(Sess,6,@Tmo,4);
 Conn:=InternetConnectA(Sess,PChar(Host),Port,Nil,Nil,3,0,0);
 If Conn=Nil Then Begin
  R.Err:='cannot connect to '+Host;
  InternetCloseHandle(Sess);Exit;
 End;
 Flags:=$80000000 or $04000000 or $00200000 or $00000200;
 If Sc='https' Then Flags:=Flags or $00800000;
 Req:=HttpOpenRequestA(Conn,PChar(R.Method),PChar(Path),Nil,Nil,Nil,Flags,0);
 If Req=Nil Then Begin
  R.Err:='cannot open request '+R.Url;
  InternetCloseHandle(Conn);InternetCloseHandle(Sess);Exit;
 End;
 Hdr:=BuildHeaders(R);
 GetMem(Buf,65536);
 UseEx:=(R.BodyFile<>'')or(Length(R.BodyStr)>0);
 Ok:=False;
 If not UseEx Then
  Ok:=HttpSendRequestA(Req,PChar(Hdr),Length(Hdr),Nil,0)<>0
 Else Begin
  FillChar(IB,SizeOf(IB),0);
  IB.dwStructSize:=SizeOf(IB);
  IB.lpcszHeader:=PChar(Hdr);
  IB.dwHeadersLength:=Length(Hdr);
  If R.BodyFile<>'' Then IB.dwBufferTotal:=LongWord(R.BodyLen)
                    Else IB.dwBufferTotal:=Length(R.BodyStr);
  If HttpSendRequestExA(Req,@IB,Nil,8,0)<>0 Then Begin
   Ok:=True;
   If R.BodyFile='' Then Begin
    Ofs:=1;
    While Ok and(Ofs<=Length(R.BodyStr))do Begin
     Want:=Length(R.BodyStr)-Ofs+1;
     If Want>65536 Then Want:=65536;
     Gt:=0;
     If InternetWriteFile(Req,@R.BodyStr[Ofs],Want,Gt)=0 Then Ok:=False;
     Inc(Ofs,Want);
    End;
   End
   Else Begin
    Assign(BF,R.BodyFile);
    {$I-}Reset(BF,1);{$I+}
    If IOResult<>0 Then Ok:=False
    Else Begin
     Seek(BF,R.BodyOfs);
     Left:=R.BodyLen;
     R.Total:=R.BodyLen;
     While Ok and(Left>0)do Begin
      Want:=65536;
      If Left<Want Then Want:=Left;
      N:=0;
      BlockRead(BF,Buf^,Want,N);
      If N<=0 Then Begin Ok:=False;Break;End;
      Gt:=0;
      If InternetWriteFile(Req,Buf,N,Gt)=0 Then Ok:=False;
      Dec(Left,N);Inc(R.Got,N);
      ShowProgress(R);
     End;
     Close(BF);
     ProgressEnd(R);
    End;
   End;
   If Ok Then Ok:=HttpEndRequestA(Req,Nil,0,0)<>0
   Else HttpEndRequestA(Req,Nil,0,0);
  End;
 End;
 If not Ok Then Begin
  R.Err:='request failed: '+R.Method+' '+R.Url;
  FreeMem(Buf);
  InternetCloseHandle(Req);InternetCloseHandle(Conn);InternetCloseHandle(Sess);
  Exit;
 End;
 L:=0;Tmo:=0;
 L:=4;
 If HttpQueryInfoA(Req,19 or $20000000,@Tmo,L,Nil)<>0 Then R.Status:=Tmo;
 SetLength(HB,32768);
 L:=32768;
 If HttpQueryInfoA(Req,22,@HB[1],L,Nil)<>0 Then Begin
  SetLength(HB,L);
  R.RespHeaders:=HB;
 End;
 Cl:=HeaderGet(R.RespHeaders,'content-length');
 R.Got:=0;R.Total:=-1;
 If Cl<>'' Then R.Total:=ToInt(Cl,-1);
 If R.Method='HEAD' Then Begin
  FreeMem(Buf);
  InternetCloseHandle(Req);InternetCloseHandle(Conn);InternetCloseHandle(Sess);
  Exit;
 End;
 OpenOut:=(R.OutFile<>'')and(R.Status>=200)and(R.Status<300);
 If OpenOut Then Begin
  MkDirs(ParentDir(R.OutFile));
  Assign(F,R.OutFile);
  If(R.Status=206)and(R.ResumeFrom>0)Then Begin
   {$I-}Reset(F,1);{$I+}
   If IOResult<>0 Then OpenOut:=False Else Begin
    Seek(F,R.ResumeFrom);
    If R.Total>0 Then R.Total:=R.Total+R.ResumeFrom;
    R.Got:=R.ResumeFrom;
   End;
  End
  Else Begin
   {$I-}Rewrite(F,1);{$I+}
   If IOResult<>0 Then OpenOut:=False;
  End;
  If not OpenOut Then R.Err:='cannot write '+R.OutFile;
 End;
 BufClear(B);
 ProgLast:=-1;
 While R.Err='' do Begin
  Gt:=0;
  If InternetReadFile(Req,Buf,65536,Gt)=0 Then Begin
   If R.Status<>0 Then R.Err:='network read error';
   Break;
  End;
  If Gt=0 Then Break;
  If OpenOut Then Begin
   BlockWrite(F,Buf^,Gt);
   Inc(R.Got,Gt);
   ShowProgress(R);
  End
  Else Begin
   SetLength(HB,Gt);
   Move(Buf^,HB[1],Gt);
   BufAdd(B,HB);
  End;
 End;
 If OpenOut Then Begin
  Close(F);
  If IOResult<>0 Then;
  ProgressEnd(R);
 End
 Else R.RespBody:=BufStr(B);
 FreeMem(Buf);
 InternetCloseHandle(Req);InternetCloseHandle(Conn);InternetCloseHandle(Sess);
End;
{$ELSE}
Function CfgQ(Const S:AnsiString):AnsiString;
Begin
 CfgQ:='"'+ReplaceAll(ReplaceAll(ReplaceAll(S,'\','\\'),'"','\"'),#10,'\n')+'"';
End;

Function TempName(Const Tag:AnsiString):AnsiString;
Var
 D:AnsiString;
Begin
 D:=GetEnv('TMPDIR');
 If D='' Then D:='/tmp';
 TempName:=DropSlash(D)+'/jirapas'+IStr(Random(1000000000))+Tag;
End;

Procedure HttpOnce(Var R:THttpReq);
Var
 Curl,Cfg,HFile,OFile,BFile,Hdr:AnsiString;
 T:Text;
 L:TSList;
 I:LongInt;
 UseBody,TmpBody:Boolean;
 Sz:Int64;
 F,G:File;
 Buf:Pointer;
 N:LongInt;
 Dat:AnsiString;
 Code:Integer;
Begin
 R.Status:=0;R.RespHeaders:='';R.RespBody:='';R.Err:='';R.Got:=0;R.Total:=-1;
 Curl:=FSearch('curl',GetEnv('PATH'));
 If Curl='' Then Begin R.Err:='curl not found (needed on non-Windows systems)';Exit;End;
 Cfg:=TempName('.cfg');HFile:=TempName('.hdr');OFile:=TempName('.out');
 BFile:='';TmpBody:=False;
 UseBody:=(R.BodyFile<>'')or(Length(R.BodyStr)>0);
 If UseBody Then Begin
  If R.BodyFile='' Then Begin
   BFile:=TempName('.body');TmpBody:=True;
   WriteAll(BFile,R.BodyStr);
  End
  Else If(R.BodyOfs=0)and(R.BodyLen=FileSizeOf(R.BodyFile))Then BFile:=R.BodyFile
  Else Begin
   BFile:=TempName('.body');TmpBody:=True;
   Assign(F,R.BodyFile);Reset(F,1);Seek(F,R.BodyOfs);
   Assign(G,BFile);Rewrite(G,1);
   GetMem(Buf,262144);
   Sz:=R.BodyLen;
   While Sz>0 do Begin
    N:=262144;If Sz<N Then N:=Sz;
    BlockRead(F,Buf^,N,N);
    If N<=0 Then Break;
    BlockWrite(G,Buf^,N);
    Dec(Sz,N);
   End;
   FreeMem(Buf);Close(F);Close(G);
  End;
 End;
 Assign(T,Cfg);
 Rewrite(T);
 WriteLn(T,'silent');
 WriteLn(T,'globoff');
 WriteLn(T,'url = ',CfgQ(R.Url));
 If R.Method='HEAD' Then WriteLn(T,'head')
 Else WriteLn(T,'request = ',CfgQ(R.Method));
 WriteLn(T,'dump-header = ',CfgQ(HFile));
 WriteLn(T,'output = ',CfgQ(OFile));
 WriteLn(T,'connect-timeout = 30');
 Hdr:=BuildHeaders(R);
 SplitStr(ReplaceAll(Hdr,#13,''),#10,L);
 For I:=0 to L.N-1 do If L.A[I]<>'' Then WriteLn(T,'header = ',CfgQ(L.A[I]));
 If UseBody Then Begin
  WriteLn(T,'header = "Expect:"');
  If Pos('content-type',LoStr(R.Headers))=0 Then WriteLn(T,'header = "Content-Type:"');
  WriteLn(T,'data-binary = ',CfgQ('@'+BFile));
 End;
 Close(T);
 DosError:=0;
 SwapVectors;
 Exec(Curl,'-K '+Cfg);
 SwapVectors;
 If DosError<>0 Then R.Err:='cannot run curl'
 Else If DosExitCode<>0 Then R.Err:='curl failed with exit code '+IStr(DosExitCode);
 If ReadAll(HFile,Dat)Then Begin
  R.RespHeaders:=LastHeaderBlock(Dat);
  R.Status:=StatusFromHeaders(R.RespHeaders);
 End;
 If R.Err='' Then Begin
  Dat:=HeaderGet(R.RespHeaders,'content-length');
  If Dat<>'' Then R.Total:=ToInt(Dat,-1);
  If R.Method<>'HEAD' Then Begin
   If(R.OutFile<>'')and(R.Status>=200)and(R.Status<300)Then Begin
    MkDirs(ParentDir(R.OutFile));
    If(R.Status=206)and(R.ResumeFrom>0)Then Begin
     { ajoute le complement au fichier partiel }
     Assign(F,OFile);Reset(F,1);
     Assign(G,R.OutFile);Reset(G,1);Seek(G,R.ResumeFrom);
     GetMem(Buf,262144);
     Repeat
      N:=0;BlockRead(F,Buf^,262144,N);
      If N>0 Then BlockWrite(G,Buf^,N);
     Until N=0;
     FreeMem(Buf);Close(F);Close(G);
     DelFile(OFile);
     R.Got:=FileSizeOf(R.OutFile);
    End
    Else Begin
     MoveFile_(OFile,R.OutFile);
     R.Got:=FileSizeOf(R.OutFile);
    End;
   End
   Else Begin
    ReadAll(OFile,R.RespBody);
    DelFile(OFile);
   End;
  End;
 End;
 DelFile(Cfg);DelFile(HFile);
 If FileExists_(OFile)Then DelFile(OFile);
 If TmpBody Then DelFile(BFile);
End;
{$ENDIF}

{ requete avec redirections manuelles : le jeton n'est envoye qu'a l'hote d'origine }
Procedure HttpDo(Var R:THttpReq);
Var
 I:LongInt;
 Loc,Host0:AnsiString;
 Tok0:AnsiString;
Begin
 Host0:=UrlHost(R.Url);
 Tok0:=R.Token;
 For I:=1 to 10 do Begin
  HttpOnce(R);
  If R.Err<>'' Then Exit;
  If(R.Status<>301)and(R.Status<>302)and(R.Status<>303)and(R.Status<>307)and(R.Status<>308)Then
    Exit;
  If not R.Follow Then Exit;
  Loc:=HeaderGet(R.RespHeaders,'location');
  If Loc='' Then Exit;
  R.Url:=ResolveUrl(R.Url,Loc);
  If UrlHost(R.Url)<>Host0 Then R.Token:='' Else R.Token:=Tok0;
  If R.Status=303 Then Begin
   R.Method:='GET';R.BodyStr:='';R.BodyFile:='';
  End;
 End;
End;
{ ------------------------------------------------------------------ }
{ Langue de l'aide : francais par defaut, anglais si LANGUAGE=EN        }
{ Les textes bilingues s'ecrivent 'English text@@Texte francais'.         }
{ ------------------------------------------------------------------ }

Function IsEn:Boolean;
Begin
 IsEn:=LoStr(Copy(TrimStr(GetEnv('LANGUAGE')),1,2))='en';
End;

Function Lg(Const En,Fr:AnsiString):AnsiString;
Begin
 If IsEn Then Lg:=En Else Lg:=Fr;
End;

{ choisit la partie du texte 'En@@Fr' selon la langue }
Function Tx(Const S:AnsiString):AnsiString;
Var
 P:LongInt;
Begin
 P:=Pos('@@',S);
 If P=0 Then Tx:=S
 Else If IsEn Then Tx:=Copy(S,1,P-1)
 Else Tx:=Copy(S,P+2,Length(S));
End;

Type
 TCmdDesc = Record
  P,D:AnsiString;
 End;

Const
 NDesc=39;
 Descs:Array[0..NDesc-1]of TCmdDesc=(
  (P:'';D:'Interactive Jira command line@@Interface en ligne de commande pour Jira'),
  (P:'board';D:'Board related commands@@Commandes li'+#130+'es aux tableaux Agile'),
  (P:'board list';D:'List all boards in a project@@Liste les tableaux d''un projet'),
  (P:'completion';D:'Output shell completion script (bash, zsh, fish, powershell)@@G'+#130+'n'+#138+'re le script de compl'+#130+'tion du shell (bash, zsh, fish, powershell)'),
  (P:'epic';D:'Manage epics in a project@@G'+#138+'re les epics d''un projet'),
  (P:'epic add';D:'Add issues to an epic@@Ajoute des tickets '+#133+' un epic'),
  (P:'epic create';D:'Create an epic in a project@@Cr'+#130+'e un epic dans un projet'),
  (P:'epic list';D:'List epics, or the issues of an epic@@Liste les epics ou les tickets d''un epic'),
  (P:'epic remove';D:'Remove issues from an epic@@Retire des tickets de leur epic'),
  (P:'init';D:'Initialize the Jira config@@Configure la connexion '+#133+' Jira'),
  (P:'issue';D:'Issue related commands@@Commandes li'+#130+'es aux tickets'),
  (P:'issue assign';D:'Assign issue to a user@@Assigne un ticket '+#133+' un utilisateur'),
  (P:'issue clone';D:'Clone an issue@@Clone un ticket'),
  (P:'issue comment';D:'Manage issue comments@@G'+#138+'re les commentaires d''un ticket'),
  (P:'issue comment add';D:'Add a comment to an issue@@Ajoute un commentaire '+#133+' un ticket'),
  (P:'issue create';D:'Create an issue in a project@@Cr'+#130+'e un ticket dans un projet'),
  (P:'issue delete';D:'Delete an issue@@Supprime un ticket'),
  (P:'issue edit';D:'Edit an issue in a project@@Modifie un ticket'),
  (P:'issue link';D:'Link two issues together@@Lie deux tickets'),
  (P:'issue link remote';D:'Add a remote web link to an issue@@Ajoute un lien web distant '+#133+' un ticket'),
  (P:'issue list';D:'List issues in a project@@Liste les tickets d''un projet'),
  (P:'issue move';D:'Transition an issue to a given state@@Change l'''+#130+'tat d''un ticket (transition)'),
  (P:'issue unlink';D:'Unlink two linked issues@@D'+#130+'lie deux tickets li'+#130+'s'),
  (P:'issue view';D:'Display issue details@@Affiche le d'+#130+'tail d''un ticket'),
  (P:'issue worklog';D:'Manage issue worklogs@@G'+#138+'re le temps de travail d''un ticket'),
  (P:'issue worklog add';D:'Add a worklog to an issue@@Ajoute du temps de travail '+#133+' un ticket'),
  (P:'man';D:'Generate man page@@G'+#130+'n'+#138+'re la page de manuel'),
  (P:'me';D:'Displays configured jira user@@Affiche l''utilisateur Jira configur'+#130+''),
  (P:'open';D:'Open issue in a browser@@Ouvre un ticket ou le projet dans le navigateur'),
  (P:'project';D:'Project related commands@@Commandes li'+#130+'es aux projets'),
  (P:'project list';D:'List all projects that a user has access to@@Liste les projets accessibles'),
  (P:'release';D:'Manage project releases@@G'+#138+'re les versions d''un projet'),
  (P:'release list';D:'List project releases@@Liste les versions d''un projet'),
  (P:'serverinfo';D:'Get Jira instance info@@Affiche les informations du serveur Jira'),
  (P:'sprint';D:'Sprint related commands@@Commandes li'+#130+'es aux sprints'),
  (P:'sprint add';D:'Add issues to a sprint@@Ajoute des tickets '+#133+' un sprint'),
  (P:'sprint close';D:'Close a sprint@@Ferme un sprint'),
  (P:'sprint list';D:'List sprints, or the issues of a sprint@@Liste les sprints ou les tickets d''un sprint'),
  (P:'version';D:'Print version information@@Affiche la version'));

Function DescOf(Const Path:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 For I:=0 to NDesc-1 do If Descs[I].P=Path Then Begin DescOf:=Tx(Descs[I].D);Exit;End;
 DescOf:='';
End;
{ ------------------------------------------------------------------ }
{ Terminal : detection, saisie                                       }
{ ------------------------------------------------------------------ }

{$IFDEF WINDOWS}
Function GetStdHandle(N:LongWord):PtrUInt;stdcall;external 'kernel32.dll' name 'GetStdHandle';
Function GetConsoleMode(H:PtrUInt;Var Mode:LongWord):LongInt;stdcall;external
  'kernel32.dll' name 'GetConsoleMode';
Function SetConsoleMode(H:PtrUInt;Mode:LongWord):LongInt;stdcall;external
  'kernel32.dll' name 'SetConsoleMode';
Function ShellExecuteA(Wnd:PtrUInt;Op,FileName,Params,Dir:PChar;Show:LongInt):PtrUInt;
 stdcall;external 'shell32.dll' name 'ShellExecuteA';
{$ENDIF}

Var
 OutTTY,InTTY,ErrTTY:Boolean;
 TermWidth:LongInt;

Procedure DetectTTY;
Var
 F:AnsiString;
 {$IFDEF WINDOWS}
 M:LongWord;
 {$ENDIF}
Begin
 OutTTY:=False;InTTY:=False;ErrTTY:=False;
 TermWidth:=ToInt(GetEnv('COLUMNS'),0);
 F:=GetEnv('JIRA_FORCE_TTY');
 If(F<>'')and(F<>'0')Then Begin
  OutTTY:=True;InTTY:=True;ErrTTY:=True;
  If ToInt(F,0)>1 Then TermWidth:=ToInt(F,0);
 End
 Else Begin
  {$IFDEF WINDOWS}
  OutTTY:=GetConsoleMode(GetStdHandle(LongWord(-11)),M)<>0;
  InTTY:=GetConsoleMode(GetStdHandle(LongWord(-10)),M)<>0;
  ErrTTY:=GetConsoleMode(GetStdHandle(LongWord(-12)),M)<>0;
  {$ELSE}
  F:=FSearch('test','/usr/bin:/bin');
  If F<>'' Then Begin
   DosError:=0;SwapVectors;Exec(F,'-t 1');SwapVectors;
   OutTTY:=(DosError=0)and(DosExitCode=0);
   DosError:=0;SwapVectors;Exec(F,'-t 0');SwapVectors;
   InTTY:=(DosError=0)and(DosExitCode=0);
   DosError:=0;SwapVectors;Exec(F,'-t 2');SwapVectors;
   ErrTTY:=(DosError=0)and(DosExitCode=0);
  End;
  {$ENDIF}
 End;
 If TermWidth<40 Then TermWidth:=100;
End;

Function PadR(Const S:AnsiString;N:LongInt):AnsiString;
Begin
 If Length(S)>=N Then PadR:=S Else PadR:=S+StringOfChar(' ',N-Length(S));
End;

{ longueur affichee (les sequences UTF-8 comptent pour un caractere) }
Function DispLen(Const S:AnsiString):LongInt;
Var
 I:LongInt;
Begin
 Result:=0;
 For I:=1 to Length(S)do If(Ord(S[I])and $C0)<>$80 Then Inc(Result);
End;

{ coupe a N caracteres affiches, avec des points de suspension }
Function Trunc_(Const S:AnsiString;N:LongInt):AnsiString;
Var
 I,C:LongInt;
Begin
 If DispLen(S)<=N Then Begin Trunc_:=S;Exit;End;
 If N<4 Then N:=4;
 C:=0;I:=1;
 While I<=Length(S)do Begin
  If(Ord(S[I])and $C0)<>$80 Then Begin
   If C>=N-3 Then Break;
   Inc(C);
  End;
  Inc(I);
 End;
 While(I<=Length(S))and((Ord(S[I])and $C0)=$80)do Inc(I);
 Trunc_:=Copy(S,1,I-1)+'...';
End;

Function PadD(Const S:AnsiString;N:LongInt):AnsiString;
Var
 D:LongInt;
Begin
 D:=DispLen(S);
 If D>=N Then PadD:=S Else PadD:=S+StringOfChar(' ',N-D);
End;

Function ReadLine_:AnsiString;
Var
 S:AnsiString;
Begin
 S:='';
 If Eof(Input)Then Begin ReadLine_:='';Exit;End;
 ReadLn(S);
 ReadLine_:=ReplaceAll(S,#13,'');
End;

{ lit tout stdin }
Function ReadStdin:AnsiString;
Var
 S,B:AnsiString;
 Bf:TBuf;
Begin
 BufClear(Bf);
 While not Eof(Input)do Begin
  ReadLn(S);
  BufAdd(Bf,ReplaceAll(S,#13,'')+#10);
 End;
 B:=BufStr(Bf);
 ReadStdin:=B;
End;

{ lit une ligne sans l'afficher (jeton) }
Function ReadSecret(Const Prompt:AnsiString):AnsiString;
Var
 S:AnsiString;
 {$IFDEF WINDOWS}
 H:PtrUInt;
 Mode:LongWord;
 Ok:Boolean;
 {$ENDIF}
Begin
 Write(Prompt);
 {$IFDEF WINDOWS}
 H:=GetStdHandle(LongWord(-10));
 Ok:=GetConsoleMode(H,Mode)<>0;
 If Ok Then SetConsoleMode(H,Mode and not LongWord(4));
 {$ELSE}
 DosError:=0;
 SwapVectors;Exec('/bin/stty','-echo');SwapVectors;
 {$ENDIF}
 ReadLn(S);
 {$IFDEF WINDOWS}
 If Ok Then SetConsoleMode(H,Mode);
 WriteLn;
 {$ELSE}
 DosError:=0;
 SwapVectors;Exec('/bin/stty','echo');SwapVectors;
 WriteLn;
 {$ENDIF}
 ReadSecret:=TrimStr(S);
End;

Procedure Die2(Const Msg:AnsiString;Code:LongInt);
Begin
 WriteLn(StdErr,Msg);
 Halt(Code);
End;

{ ------------------------------------------------------------------ }
{ Analyse de la ligne de commande et aide (style cobra)               }
{ ------------------------------------------------------------------ }

Const
 MaxOpt=80;

Type
 TOptDef = Record
  Long,Short,Meta,Help:AnsiString;
  Multi:Boolean;
 End;

Var
 CmdPath,CmdUsage,CmdLongDesc,CmdJsonFields:AnsiString;
 GlobalFrom:LongInt;
 CmdAliases,CmdExamples:TSList;
 ODef:Array[0..MaxOpt-1]of TOptDef;
 ONum:LongInt;
 OVals:Array[0..MaxOpt-1]of TSList;
 OSet:Array[0..MaxOpt-1]of Boolean;
 PosArgs:TSList;
 ArgStart:LongInt;
 JsonListing:Boolean;
 StopAfter:LongInt;

Procedure CmdBegin(Const Path,Usage:AnsiString);
Var
 I:LongInt;
Begin
 CmdPath:=Path;CmdUsage:=Usage;CmdLongDesc:='';CmdJsonFields:='';
 SClear(CmdAliases);SClear(CmdExamples);
 For I:=0 to MaxOpt-1 do Begin SClear(OVals[I]);OSet[I]:=False;End;
 ONum:=0;GlobalFrom:=MaxOpt;SClear(PosArgs);JsonListing:=False;StopAfter:=0;
End;

Procedure CmdLong(Const S:AnsiString);
Begin
 CmdLongDesc:=S;
End;

Procedure CmdAlias(Const S:AnsiString);
Begin
 SAdd(CmdAliases,S);
End;

Procedure CmdExample(Const S:AnsiString);
Begin
 SAdd(CmdExamples,S);
End;

Procedure CmdJson(Const Fields:AnsiString);
Begin
 CmdJsonFields:=Fields;
End;

{ Meta='' : option sans valeur ; Meta commencant par '*' : option repetable }
Procedure Opt(Const Long,Short,Meta,Help:AnsiString);
Begin
 ODef[ONum].Long:=Long;
 ODef[ONum].Short:=Short;
 ODef[ONum].Multi:=(Meta<>'')and(Meta[1]='*');
 If ODef[ONum].Multi Then ODef[ONum].Meta:=Copy(Meta,2,Length(Meta))
                     Else ODef[ONum].Meta:=Meta;
 ODef[ONum].Help:=Help;
 Inc(ONum);
End;

Var
 Ptr_:LongInt;

Function LastDelimPos(Const S:AnsiString):LongInt;
Var
 I:LongInt;
Begin
 I:=Length(S);
 While(I>0)and(S[I]<>' ')do Dec(I);
 LastDelimPos:=I;
End;

Function FindOpt(Const Name:AnsiString;IsShort:Boolean):LongInt;forward;

{ options globales de jira : -c, -p et --debug }
Var
 CfgOverride,ProjOverride:AnsiString;
 DebugOn:Boolean;

Procedure OptG;
Begin
 GlobalFrom:=ONum;
 Opt('config','c','string','Config file (default is $HOME/.config/.jira/.config.yml)@@Fichier de configuration (d'+#130+'faut : $HOME/.config/.jira/.config.yml)');
 Opt('debug','','','Turn on debug output@@Active la sortie de d'+#130+'bogage');
 Opt('project','p','string','Jira project to look into (defaults to project in the config file)@@Projet Jira '+#133+' utiliser (d'+#130+'faut : projet du fichier de configuration)');
End;

Procedure PrintCmdHelp;
Var
 I,W,K:LongInt;
 Ls:TSList;
 S,D:AnsiString;
Begin
 D:=DescOf(CmdPath);
 If D<>'' Then WriteLn(D);
 If CmdLongDesc<>'' Then Begin If D<>'' Then WriteLn;WriteLn(Tx(CmdLongDesc));End;
 WriteLn;
 WriteLn(Lg('Usage:','Utilisation :'));
 WriteLn('  jira ',CmdPath,IfThen_(CmdUsage<>'',' '+CmdUsage,''),' [flags]');
 If CmdAliases.N>0 Then Begin
  WriteLn;
  WriteLn(Lg('Aliases:','Alias :'));
  S:='';
  For I:=0 to CmdAliases.N-1 do Begin
   If I>0 Then S:=S+', ';
   S:=S+CmdAliases.A[I];
  End;
  I:=Length(CmdPath);
  While(I>0)and(CmdPath[I]<>' ')do Dec(I);
  WriteLn('  ',Copy(CmdPath,I+1,Length(CmdPath)),', ',S);
 End;
 If CmdExamples.N>0 Then Begin
  WriteLn;
  WriteLn(Lg('Examples:','Exemples :'));
  For I:=0 to CmdExamples.N-1 do WriteLn(Tx(CmdExamples.A[I]));
 End;
 For K:=0 to 1 do Begin
  SClear(Ls);
  W:=0;
  For I:=0 to ONum-1 do
   If((K=0)and(I<GlobalFrom))or((K=1)and(I>=GlobalFrom))Then Begin
    If ODef[I].Short<>'' Then S:='-'+ODef[I].Short+', ' Else S:='    ';
    S:=S+'--'+ODef[I].Long;
    If ODef[I].Meta<>'' Then Begin
     If ODef[I].Multi Then S:=S+' stringArray' Else S:=S+' '+ODef[I].Meta;
    End;
    SAdd(Ls,S);
    If Length(S)>W Then W:=Length(S);
   End;
  If K=0 Then Begin
   WriteLn;
   WriteLn(Lg('Flags:','Options :'));
   WriteLn('  ',PadR('-h, --help',W),'   ',Lg('Help for ','Aide de '),Copy(CmdPath,LastDelimPos(CmdPath)+1,Length(CmdPath)));
   If W<10 Then W:=10;
  End
  Else Begin
   If Ls.N=0 Then Break;
   WriteLn;
   WriteLn(Lg('Global Flags:','Options globales :'));
  End;
  Ptr_:=0;
  For I:=0 to ONum-1 do
   If((K=0)and(I<GlobalFrom))or((K=1)and(I>=GlobalFrom))Then Begin
    WriteLn('  ',PadR(Ls.A[Ptr_],W),'   ',Tx(ODef[I].Help));
    Inc(Ptr_);
   End;
 End;
 WriteLn;
 WriteLn(Lg('Use "jira ','Utilisez "jira '),CmdPath,Lg(' [command] --help" for more information about a command.',' [commande] --help" pour plus d''informations.'));
End;

Procedure FlagErr(Const Msg:AnsiString);
Begin
 WriteLn(StdErr,'Error: ',Msg);
 WriteLn(StdErr,Lg('Run ''jira ','Ex'+#130+'cutez ''jira '),CmdPath,Lg(' --help'' for usage.',' --help'' pour l''aide.'));
 Halt(1);
End;

Procedure UsageErr(Const Msg:AnsiString);
Begin
 FlagErr(Tx(Msg));
End;

Function FindOpt(Const Name:AnsiString;IsShort:Boolean):LongInt;
Var
 I:LongInt;
Begin
 FindOpt:=-1;
 For I:=0 to ONum-1 do
  If(IsShort and(ODef[I].Short=Name))or((not IsShort)and(ODef[I].Long=Name))Then Begin
   FindOpt:=I;Exit;
  End;
End;

Procedure SetOptVal(K:LongInt;Const V:AnsiString);
Begin
 OSet[K]:=True;
 If(not ODef[K].Multi)and(OVals[K].N>0)Then OVals[K].A[0]:=V Else SAdd(OVals[K],V);
End;

Procedure ParseArgs(First:LongInt);
Var
 I,K,P,J:LongInt;
 Fl:TSList;
 A,Nm,V:AnsiString;
 Rest:Boolean;
Begin
 Rest:=False;
 I:=First;
 While I<=ParamCount do Begin
  A:=ParamStr(I);
  If Rest or((StopAfter>0)and(PosArgs.N>=StopAfter))Then SAdd(PosArgs,A)
  Else If A='--' Then Rest:=True
  Else If((A='-h')and(FindOpt('h',True)<0))or(A='--help')or(A='/?')Then Begin PrintCmdHelp;Halt(0);End
  Else If StartsWith(A,'--')Then Begin
   Nm:=Copy(A,3,Length(A));V:='';
   P:=Pos('=',Nm);
   If P>0 Then Begin V:=Copy(Nm,P+1,Length(Nm));Nm:=Copy(Nm,1,P-1);End;
   K:=FindOpt(Nm,False);
   If K<0 Then FlagErr(Lg('unknown flag: --','option inconnue : --')+Nm);
   If ODef[K].Meta='' Then Begin
    If P>0 Then Begin
     If LoStr(V)='false' Then OSet[K]:=False
     Else If LoStr(V)='true' Then OSet[K]:=True
     Else FlagErr(Lg('invalid argument "'+V+'" for "--'+Nm+'" flag: strconv.ParseBool: parsing "'+V+
       '": invalid syntax','argument invalide "'+V+'" pour l''option "--'+Nm+'"'));
    End
    Else OSet[K]:=True;
   End
   Else If(Pos('[=',ODef[K].Meta)>0)and(P=0)Then SetOptVal(K,'last')
   Else Begin
    If P=0 Then Begin
     If I>=ParamCount Then Begin
      If Nm='json' Then Begin JsonListing:=True;OSet[K]:=True;Inc(I);Continue;End;
      FlagErr(Lg('flag needs an argument: --','l''option requiert un argument : --')+Nm);
     End;
     Inc(I);V:=ParamStr(I);
    End;
    SetOptVal(K,V);
   End;
  End
  Else If(Length(A)>=2)and(A[1]='-')and not(A[2]in['0'..'9'])Then Begin
   J:=2;
   While J<=Length(A)do Begin
    Nm:=Copy(A,J,1);
    K:=FindOpt(Nm,True);
    If K<0 Then FlagErr(Lg('unknown shorthand flag: ''','option courte inconnue : ''')+Nm+''' in '+A);
    If ODef[K].Meta='' Then OSet[K]:=True
    Else Begin
     If J<Length(A)Then V:=Copy(A,J+1,Length(A))
     Else Begin
      If I>=ParamCount Then FlagErr(Lg('flag needs an argument: ''','l''option requiert un argument : ''')+
        Nm+''' in -'+Nm);
      Inc(I);V:=ParamStr(I);
     End;
     If(Length(V)>0)and(V[1]='=')and(J<Length(A))Then Delete(V,1,1);
     SetOptVal(K,V);
     Break;
    End;
    Inc(J);
   End;
  End
  Else SAdd(PosArgs,A);
  Inc(I);
 End;
End;

Procedure ParseArgsStop;
Begin
 StopAfter:=1;
 ParseArgs(ArgStart);
End;

Procedure NeedArgs(Min,Max:LongInt);
Begin
 If PosArgs.N<Min Then Begin
  If Min=Max Then FlagErr('accepts '+IStr(Min)+' arg(s), received '+IStr(PosArgs.N))
  Else FlagErr('requires at least '+IStr(Min)+' arg(s), only received '+IStr(PosArgs.N));
 End;
 If(Max>=0)and(PosArgs.N>Max)Then Begin
  If Min=Max Then FlagErr('accepts '+IStr(Min)+' arg(s), received '+IStr(PosArgs.N))
  Else FlagErr('accepts at most '+IStr(Max)+' arg(s), received '+IStr(PosArgs.N));
 End;
End;

Function OptHas(Const Long:AnsiString):Boolean;
Var
 K:LongInt;
Begin
 K:=FindOpt(Long,False);
 OptHas:=(K>=0)and OSet[K];
End;

Function OptGet(Const Long:AnsiString):AnsiString;
Var
 K:LongInt;
Begin
 OptGet:='';
 K:=FindOpt(Long,False);
 If(K>=0)and(OVals[K].N>0)Then OptGet:=OVals[K].A[OVals[K].N-1];
End;

Function OptGetDef(Const Long,Def:AnsiString):AnsiString;
Begin
 If OptHas(Long)Then OptGetDef:=OptGet(Long) Else OptGetDef:=Def;
End;

Function OptInt(Const Long:AnsiString;Def:Int64):Int64;
Var
 V:Int64;
Begin
 If OptHas(Long)Then Begin
  V:=ToInt(OptGet(Long),-999999999);
  If V=-999999999 Then FlagErr('invalid argument "'+OptGet(Long)+'" for "--'+Long+
    '" flag: strconv.ParseInt: parsing "'+OptGet(Long)+'": invalid syntax');
  OptInt:=V;
 End
 Else OptInt:=Def;
End;

Procedure OptList(Const Long:AnsiString;Var L:TSList);
Var
 K,I:LongInt;
Begin
 SClear(L);
 K:=FindOpt(Long,False);
 If K>=0 Then For I:=0 to OVals[K].N-1 do SAdd(L,OVals[K].A[I]);
End;

{ liste d'une option repetable ou separee par des virgules }
Procedure OptCsv(Const Long:AnsiString;Var L:TSList);
Var
 K,I,J:LongInt;
 T:TSList;
Begin
 SClear(L);
 K:=FindOpt(Long,False);
 If K<0 Then Exit;
 For I:=0 to OVals[K].N-1 do Begin
  SplitStr(OVals[K].A[I],',',T);
  For J:=0 to T.N-1 do If TrimStr(T.A[J])<>'' Then SAdd(L,TrimStr(T.A[J]));
 End;
End;

Function Pos1(I:LongInt):AnsiString;
Begin
 If I<PosArgs.N Then Pos1:=PosArgs.A[I] Else Pos1:='';
End;

Procedure Excl(Const A,B:AnsiString);
Begin
 If OptHas(A)and OptHas(B)Then
   Die2(Lg('specify only one of `--'+A+'` or `--'+B+'`','sp'+#130+'cifiez seulement `--'+A+'` ou `--'+B+'`'),1);
End;

Procedure MustFlag(Const A:AnsiString);
Begin
 If not OptHas(A)Then Die2(Lg('required flag(s) "'+A+'" not set','option(s) obligatoire(s) "'+A+'" non d'+
   ''+#130+'finie(s)'),1);
End;
{ ------------------------------------------------------------------ }
{ Processus externes (git, navigateur, editeur)                       }
{ ------------------------------------------------------------------ }

Function TmpFile(Const Tag:AnsiString):AnsiString;
Var
 D:AnsiString;
Begin
 D:=GetEnv('TMPDIR');
 If D='' Then D:=GetEnv('TEMP');
 If D='' Then D:=GetEnv('TMP');
 {$IFDEF WINDOWS}
 If D='' Then D:='.';
 {$ELSE}
 If D='' Then D:='/tmp';
 {$ENDIF}
 TmpFile:=DropSlash(D)+DS+'jirapas'+IStr(Random(1000000000))+Tag;
End;

{ guillemets d'un argument pour le shell }
Function Q(Const S:AnsiString):AnsiString;
Begin
 {$IFDEF WINDOWS}
 Q:='"'+ReplaceAll(S,'"','\"')+'"';
 {$ELSE}
 Q:=''''+ReplaceAll(S,'''','''\''''')+'''';
 {$ENDIF}
End;

{ execute une ligne de commande par le shell ; renvoie le code de sortie }
Function RunShell(Const Cmd:AnsiString):LongInt;
Var
 Scr:AnsiString;
 T:Text;
Begin
 {$IFDEF WINDOWS}
 Scr:=TmpFile('.cmd');
 Assign(T,Scr);Rewrite(T);
 Write(T,'@echo off'#13#10,Cmd,#13#10);
 Close(T);
 DosError:=0;
 SwapVectors;
 Exec(GetEnv('COMSPEC'),'/C "'+Scr+'"');
 SwapVectors;
 {$ELSE}
 Scr:=TmpFile('.sh');
 Assign(T,Scr);Rewrite(T);
 Write(T,Cmd,#10);
 Close(T);
 DosError:=0;
 SwapVectors;
 Exec('/bin/sh',Scr);
 SwapVectors;
 {$ENDIF}
 DelFile(Scr);
 If DosError<>0 Then RunShell:=127 Else RunShell:=DosExitCode;
End;

{ execute et capture la sortie standard (et l'erreur si Both) }
Function RunCapture(Const Cmd:AnsiString;Var Output:AnsiString;Both:Boolean):LongInt;
Var
 F:AnsiString;
Begin
 F:=TmpFile('.out');
 If Both Then RunCapture:=RunShell(Cmd+' > '+Q(F)+' 2>&1')
         Else RunCapture:=RunShell(Cmd+' > '+Q(F));
 If not ReadAll(F,Output)Then Output:='';
 DelFile(F);
End;

Const
 {$IFDEF WINDOWS}
 NullDev='nul';
 {$ELSE}
 NullDev='/dev/null';
 {$ENDIF}

Function WhichCmd(Const Name:AnsiString):AnsiString;
Begin
 {$IFDEF WINDOWS}
 WhichCmd:=FSearch(Name+'.exe',GetEnv('PATH'));
 If WhichCmd='' Then WhichCmd:=FSearch(Name,GetEnv('PATH'));
 {$ELSE}
 WhichCmd:=FSearch(Name,GetEnv('PATH'));
 {$ENDIF}
End;

Procedure OpenBrowser(Const Url:AnsiString);
Var
 B:AnsiString;
Begin
 B:=GetEnv('JIRA_BROWSER');
  If B='' Then B:=GetEnv('BROWSER');
 If B<>'' Then Begin RunShell(B+' '+Q(Url));Exit;End;
 {$IFDEF WINDOWS}
 ShellExecuteA(0,'open',PChar(Url),Nil,Nil,1);
 {$ELSE}
 If WhichCmd('xdg-open')<>'' Then RunShell('xdg-open '+Q(Url)+' >/dev/null 2>&1')
 Else If WhichCmd('open')<>'' Then RunShell('open '+Q(Url))
 Else If WhichCmd('wslview')<>'' Then RunShell('wslview '+Q(Url))
 Else WriteLn(StdErr,'could not find a browser to open ',Url);
 {$ENDIF}
End;

{ ouvre l'editeur sur un fichier temporaire contenant Init ; renvoie le nouveau texte }
Function EditText(Const Init,Ext:AnsiString):AnsiString;
Var
 Ed,F,S:AnsiString;
Begin
 Ed:=GetEnv('JIRA_EDITOR');
 If Ed='' Then Ed:=GetEnv('VISUAL');
 If Ed='' Then Ed:=GetEnv('EDITOR');
 {$IFDEF WINDOWS}
 If Ed='' Then Ed:='notepad';
 {$ELSE}
 If Ed='' Then Ed:='vi';
 {$ENDIF}
 F:=TmpFile(Ext);
 WriteAll(F,Init);
 If RunShell(Ed+' '+Q(F))<>0 Then Begin DelFile(F);Die('failed to run editor: '+Ed);End;
 If not ReadAll(F,S)Then S:='';
 DelFile(F);
 EditText:=ReplaceAll(S,#13,'');
End;

{ ------------------------------------------------------------------ }
{ Mini YAML (config.yml, hosts.yml) : cles imbriquees "a|b|c"          }
{ ------------------------------------------------------------------ }

Type
 TYaml = Record
  K,V:TSList;
 End;

Function YamlUnq(Const S:AnsiString):AnsiString;
Var
 T:AnsiString;
Begin
 T:=TrimStr(S);
 If(Length(T)>=2)and(T[1]='''')and(T[Length(T)]='''')Then
   YamlUnq:=ReplaceAll(Copy(T,2,Length(T)-2),'''''','''')
 Else If(Length(T)>=2)and(T[1]='"')and(T[Length(T)]='"')Then
   YamlUnq:=ReplaceAll(ReplaceAll(Copy(T,2,Length(T)-2),'\"','"'),'\\','\')
 Else YamlUnq:=T;
End;

Function YamlQ(Const S:AnsiString):AnsiString;
Var
 Bad:Boolean;
Begin
 Bad:=(S='')or(S[1]in[' ','!','*','&','%','@','`','-','?','#',',','[',']','{','}','>','|','''','"'])
   or(S[Length(S)]=' ')or(Pos(': ',S)>0)or(Pos(' #',S)>0)or(S[Length(S)]=':');
 If(S='true')or(S='false')or(S='null')or(S='~')Then Bad:=True;
 If Bad Then YamlQ:=''''+ReplaceAll(S,'''','''''')+'''' Else YamlQ:=S;
End;

Procedure YamlLoad(Const Path:AnsiString;Var Y:TYaml);
Var
 Txt,Ln,Key,Val:AnsiString;
 L:TSList;
 I,J,Ind,P:LongInt;
 Stk:Array[0..15]of AnsiString;
 StkInd:Array[0..15]of LongInt;
 Sp,C:LongInt;
 Full:AnsiString;
Begin
 SClear(Y.K);SClear(Y.V);
 If not ReadAll(Path,Txt)Then Exit;
 SplitStr(ReplaceAll(Txt,#13,''),#10,L);
 Sp:=0;
 For I:=0 to L.N-1 do Begin
  Ln:=L.A[I];
  If(TrimStr(Ln)='')or(TrimStr(Ln)[1]='#')Then Continue;
  Ind:=0;
  While(Ind<Length(Ln))and(Ln[Ind+1]=' ')do Inc(Ind);
  Ln:=Copy(Ln,Ind+1,Length(Ln));
  P:=0;
  For J:=1 to Length(Ln)do
   If(Ln[J]=':')and((J=Length(Ln))or(Ln[J+1]=' '))Then Begin P:=J;Break;End;
  If P=0 Then Continue;
  { les cles entre guillemets peuvent contenir ':' }
  If(Ln[1]='''')or(Ln[1]='"')Then Begin
   C:=Pos(Ln[1],Copy(Ln,2,Length(Ln)));
   If C>0 Then Begin
    Key:=YamlUnq(Copy(Ln,1,C+1));
    P:=C+2;
    Val:=TrimStr(Copy(Ln,P+1,Length(Ln)));
   End
   Else Begin Key:=YamlUnq(Copy(Ln,1,P-1));Val:=TrimStr(Copy(Ln,P+1,Length(Ln)));End;
  End
  Else Begin
   Key:=TrimStr(Copy(Ln,1,P-1));
   Val:=TrimStr(Copy(Ln,P+1,Length(Ln)));
  End;
  While(Sp>0)and(StkInd[Sp-1]>=Ind)do Dec(Sp);
  Full:='';
  For J:=0 to Sp-1 do Full:=Full+Stk[J]+'|';
  Full:=Full+Key;
  If Val='' Then Begin
   If Sp<16 Then Begin Stk[Sp]:=Key;StkInd[Sp]:=Ind;Inc(Sp);End;
   If(I+1>=L.N)or(Pos(':',L.A[I+1])=0)Then Begin SAdd(Y.K,Full);SAdd(Y.V,'');End;
  End
  Else Begin
   SAdd(Y.K,Full);SAdd(Y.V,YamlUnq(Val));
  End;
 End;
End;

Function YGet(Const Y:TYaml;Const Key:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 I:=SIndex(Y.K,Key);
 If I>=0 Then YGet:=Y.V.A[I] Else YGet:='';
End;

Function YHas(Const Y:TYaml;Const Key:AnsiString):Boolean;
Begin
 YHas:=SIndex(Y.K,Key)>=0;
End;

Function CommonPrefix(Const A,B:AnsiString):LongInt;
Var
 I,L,Segs:LongInt;
Begin
 Segs:=0;L:=0;
 For I:=1 to Length(A)do Begin
  If(I>Length(B))or(A[I]<>B[I])Then Break;
  If A[I]='|' Then Segs:=I;
 End;
 CommonPrefix:=Segs;
End;

Procedure YSet(Var Y:TYaml;Const Key,Val:AnsiString);
Var
 I,Best,BestLen,Cp,J:LongInt;
Begin
 I:=SIndex(Y.K,Key);
 If I>=0 Then Begin Y.V.A[I]:=Val;Exit;End;
 Best:=-1;BestLen:=0;
 For I:=0 to Y.K.N-1 do Begin
  Cp:=CommonPrefix(Y.K.A[I],Key);
  If Cp>=BestLen Then Begin
   If(Cp>BestLen)or(Cp>0)Then Begin Best:=I;BestLen:=Cp;End;
  End;
 End;
 If Best<0 Then Begin SAdd(Y.K,Key);SAdd(Y.V,Val);Exit;End;
 SAdd(Y.K,'');SAdd(Y.V,'');
 For J:=Y.K.N-1 downto Best+2 do Begin Y.K.A[J]:=Y.K.A[J-1];Y.V.A[J]:=Y.V.A[J-1];End;
 Y.K.A[Best+1]:=Key;Y.V.A[Best+1]:=Val;
End;

{ supprime la cle et tout ce qui est dessous }
Procedure YDel(Var Y:TYaml;Const Key:AnsiString);
Var
 I,J:LongInt;
Begin
 J:=0;
 For I:=0 to Y.K.N-1 do
  If(Y.K.A[I]<>Key)and not StartsWith(Y.K.A[I],Key+'|')Then Begin
   Y.K.A[J]:=Y.K.A[I];Y.V.A[J]:=Y.V.A[I];Inc(J);
  End;
 Y.K.N:=J;Y.V.N:=J;
End;

Function YSub(Const Y:TYaml;Const Prefix:AnsiString;Var Names:TSList):LongInt;
Var
 I,P:LongInt;
 R,Nm:AnsiString;
Begin
 SClear(Names);
 For I:=0 to Y.K.N-1 do
  If StartsWith(Y.K.A[I],Prefix)Then Begin
   R:=Copy(Y.K.A[I],Length(Prefix)+1,Length(Y.K.A[I]));
   P:=Pos('|',R);
   If P>0 Then Nm:=Copy(R,1,P-1) Else Nm:=R;
   If SIndex(Names,Nm)<0 Then SAdd(Names,Nm);
  End;
 YSub:=Names.N;
End;

Function YamlSave(Const Path:AnsiString;Const Y:TYaml):Boolean;
Var
 B:TBuf;
 I,J,Depth:LongInt;
 Seg,PSeg:TSList;
Begin
 BufClear(B);
 SClear(PSeg);
 For I:=0 to Y.K.N-1 do Begin
  SplitStr(Y.K.A[I],'|',Seg);
  Depth:=0;
  While(Depth<Seg.N-1)and(Depth<PSeg.N-1)and(Seg.A[Depth]=PSeg.A[Depth])do Inc(Depth);
  For J:=Depth to Seg.N-2 do
    BufAdd(B,StringOfChar(' ',J*4)+YamlQ(Seg.A[J])+':'#10);
  BufAdd(B,StringOfChar(' ',(Seg.N-1)*4)+YamlQ(Seg.A[Seg.N-1])+':');
  If Y.V.A[I]<>'' Then BufAdd(B,' '+YamlQ(Y.V.A[I]));
  BufAdd(B,#10);
  PSeg:=Seg;
 End;
 YamlSave:=WriteAll(Path,BufStr(B));
End;

{ ------------------------------------------------------------------ }
{ Configuration de jira (~/.config/.jira/.config.yml)                 }
{ ------------------------------------------------------------------ }

Var
 TokenCache:AnsiString;
 CfgY:TYaml;
 JServer,JLogin,JInstall,JAuth,JProject,JProjType:AnsiString;
 JBoardId,JBoardName,JEpicName,JEpicLink:AnsiString;
 CfgLoaded,CfgExists:Boolean;

Function ConfigFile:AnsiString;
Var
 D:AnsiString;
Begin
 If CfgOverride<>'' Then Begin ConfigFile:=CfgOverride;Exit;End;
 D:=GetEnv('JIRA_CONFIG_FILE');
 If D<>'' Then Begin ConfigFile:=D;Exit;End;
 D:=GetEnv('XDG_CONFIG_HOME');
 If D='' Then D:=JoinPath(HomeDir,'.config');
 ConfigFile:=JoinPath(JoinPath(D,'.jira'),'.config.yml');
End;

Function StripSlash(Const S:AnsiString):AnsiString;
Begin
 StripSlash:=S;
 While(StripSlash<>'')and(StripSlash[Length(StripSlash)]='/')do Delete(StripSlash,Length(StripSlash),1);
End;

Function NetrcFile:AnsiString;
Begin
 {$IFDEF WINDOWS}
 NetrcFile:=JoinPath(HomeDir,'_netrc');
 If not FileExists_(NetrcFile)Then NetrcFile:=JoinPath(HomeDir,'.netrc');
 {$ELSE}
 NetrcFile:=JoinPath(HomeDir,'.netrc');
 {$ENDIF}
End;

{ mot de passe de ~/.netrc pour l'hote ; Login renseigne si trouve }
Function NetrcPassword(Const Host_:AnsiString;Var Login:AnsiString):AnsiString;
Var
 Txt:AnsiString;
 T,L:TSList;
 I,J:LongInt;
 Cur,Lg_,Pw:AnsiString;
 Hit:Boolean;
Begin
 NetrcPassword:='';Login:='';
 If not ReadAll(NetrcFile,Txt)Then Exit;
 SClear(T);
 SplitStr(ReplaceAll(ReplaceAll(Txt,#13,' '),#10,' '),' ',L);
 For I:=0 to L.N-1 do If L.A[I]<>'' Then SAdd(T,L.A[I]);
 Hit:=False;Lg_:='';Pw:='';Cur:='';
 I:=0;
 While I<T.N do Begin
  If T.A[I]='machine' Then Begin
   If Hit and(Pw<>'')Then Break;
   Hit:=(I+1<T.N)and(T.A[I+1]=Host_);
   Lg_:='';Pw:='';
   Inc(I,2);Continue;
  End;
  If T.A[I]='default' Then Begin
   If Hit and(Pw<>'')Then Break;
   Hit:=True;Lg_:='';Pw:='';
   Inc(I);Continue;
  End;
  If Hit and(I+1<T.N)Then Begin
   If T.A[I]='login' Then Begin Lg_:=T.A[I+1];Inc(I,2);Continue;End;
   If T.A[I]='password' Then Begin Pw:=T.A[I+1];Inc(I,2);Continue;End;
  End;
  Inc(I);
 End;
 If Hit and(Pw<>'')Then Begin NetrcPassword:=Pw;Login:=Lg_;End;
End;

Procedure LoadJiraConfig;
Var
 F:AnsiString;
Begin
 F:=ConfigFile;
 CfgExists:=FileExists_(F);
 YamlLoad(F,CfgY);
 CfgLoaded:=True;
 JServer:=StripSlash(YGet(CfgY,'server'));
 JLogin:=YGet(CfgY,'login');
 JInstall:=YGet(CfgY,'installation');
 JAuth:=YGet(CfgY,'auth_type');
 JProject:=YGet(CfgY,'project|key');
 JProjType:=YGet(CfgY,'project|type');
 JBoardId:=YGet(CfgY,'board|id');
 JBoardName:=YGet(CfgY,'board|name');
 JEpicName:=YGet(CfgY,'epic|name');
 JEpicLink:=YGet(CfgY,'epic|link');
 If GetEnv('JIRA_SERVER')<>'' Then JServer:=StripSlash(GetEnv('JIRA_SERVER'));
 If GetEnv('JIRA_LOGIN')<>'' Then JLogin:=GetEnv('JIRA_LOGIN');
 If GetEnv('JIRA_INSTALLATION')<>'' Then JInstall:=GetEnv('JIRA_INSTALLATION');
 If GetEnv('JIRA_AUTH_TYPE')<>'' Then JAuth:=GetEnv('JIRA_AUTH_TYPE');
 If JAuth='' Then JAuth:='basic';
 JAuth:=LoStr(JAuth);
 If JInstall='' Then JInstall:='Cloud';
 If LoStr(JInstall)='local' Then JInstall:='Local' Else JInstall:='Cloud';
 If ProjOverride<>'' Then JProject:=ProjOverride;
End;

Function IsCloud:Boolean;
Begin
 IsCloud:=JInstall='Cloud';
End;

{ applique les options globales (-c, -p, --debug) puis charge la configuration }
Procedure ApplyGlobals;
Begin
 CfgOverride:=OptGet('config');
 ProjOverride:=OptGet('project');
 DebugOn:=OptHas('debug');
 LoadJiraConfig;
End;

Procedure SaveJiraConfig;
Var
 F:AnsiString;
Begin
 F:=ConfigFile;
 MkDirs(ParentDir(F));
 If not YamlSave(F,CfgY)Then Die('failed to write '+F);
End;

Function HostOfServer:AnsiString;
Begin
 HostOfServer:=UrlHost(JServer);
End;

{ jeton d'API : JIRA_API_TOKEN, sinon ~/.netrc }
Function ApiToken:AnsiString;
Var
 Lg_:AnsiString;
Begin
 If TokenCache<>'' Then Begin ApiToken:=TokenCache;Exit;End;
 ApiToken:=GetEnv('JIRA_API_TOKEN');
 If ApiToken='' Then Begin
  ApiToken:=NetrcPassword(HostOfServer,Lg_);
  If(JLogin='')and(Lg_<>'')Then JLogin:=Lg_;
 End;
End;

Function AuthValue:AnsiString;
Var
 Tk:AnsiString;
Begin
 Tk:=ApiToken;
 If Tk='' Then Begin
  WriteLn(StdErr,Lg('Error: missing API token. Export it with:  export JIRA_API_TOKEN=<token>',
    'Erreur : jeton d''API manquant. D'+#130+'finissez-le avec :  export JIRA_API_TOKEN=<jeton>'));
  Halt(1);
 End;
 If(JAuth='bearer')or(JLogin='')Then AuthValue:='Bearer '+Tk
 Else AuthValue:='Basic '+B64Str(JLogin+':'+Tk);
End;

Procedure RequireConfig;
Begin
 If JServer='' Then Begin
  WriteLn(StdErr,Lg('Missing configuration file.','Fichier de configuration manquant.'));
  WriteLn(StdErr,Lg('Run ''jira init'' to generate the config.','Ex'+#130+'cutez ''jira init'' pour g'+#130+'n'+#130+'rer la configuration.'));
  Halt(1);
 End;
End;

{ projet obligatoire pour la commande }
Function NeedProject:AnsiString;
Begin
 If JProject='' Then Begin
  WriteLn(StdErr,Lg('Error: project not set. Use -p/--project or run ''jira init''.',
    'Erreur : projet non d'+#130+'fini. Utilisez -p/--project ou ex'+#130+'cutez ''jira init''.'));
  Halt(1);
 End;
 NeedProject:=JProject;
End;
{ ------------------------------------------------------------------ }
{ Constructeurs JSON                                                  }
{ ------------------------------------------------------------------ }

{ ajoute "cle":"valeur" }
Procedure FS(Var L:TSList;Const K,V:AnsiString);
Begin
 SAdd(L,JQ(K)+':'+JQ(V));
End;

{ ajoute "cle":valeur (JSON brut) }
Procedure FR(Var L:TSList;Const K,V:AnsiString);
Begin
 SAdd(L,JQ(K)+':'+V);
End;

Procedure FB(Var L:TSList;Const K:AnsiString;B:Boolean);
Begin
 SAdd(L,JQ(K)+':'+JBool(B));
End;

Procedure FN(Var L:TSList;Const K:AnsiString;N:Int64);
Begin
 SAdd(L,JQ(K)+':'+IStr(N));
End;

Function JoinList(Const L:TSList;Const Sep:AnsiString):AnsiString;
Var
 I:LongInt;
 B:TBuf;
Begin
 BufClear(B);
 For I:=0 to L.N-1 do Begin
  If I>0 Then BufAdd(B,Sep);
  BufAdd(B,L.A[I]);
 End;
 JoinList:=BufStr(B);
End;

Function ObjOf(Const L:TSList):AnsiString;
Begin
 ObjOf:='{'+JoinList(L,',')+'}';
End;

{ tableau JSON de chaines }
Function StrArr(Const L:TSList):AnsiString;
Var
 I:LongInt;
 B:TBuf;
Begin
 BufClear(B);
 BufAdd(B,'[');
 For I:=0 to L.N-1 do Begin
  If I>0 Then BufAdd(B,',');
  BufAdd(B,JQ(L.A[I]));
 End;
 BufAdd(B,']');
 StrArr:=BufStr(B);
End;


{ renvoie une copie JSON brute d'un noeud }
Function RawJson(N:LongInt):AnsiString;
Var
 B:TBuf;
 Function Walk(X:LongInt):AnsiString;
 Var
  C:LongInt;
  T:TSList;
 Begin
  If X<0 Then Begin Walk:='null';Exit;End;
  Case JP[X].Kind of
   JK_NULL:Walk:='null';
   JK_BOOL,JK_NUM:Walk:=JP[X].S;
   JK_STR:Walk:=JQ(JP[X].S);
   Else Begin
    SClear(T);
    C:=JP[X].First;
    While C>=0 do Begin
     If JP[X].Kind=JK_OBJ Then SAdd(T,JQ(JP[C].Key)+':'+Walk(C)) Else SAdd(T,Walk(C));
     C:=JP[C].Next;
    End;
    If JP[X].Kind=JK_OBJ Then Walk:='{'+JoinList(T,',')+'}' Else Walk:='['+JoinList(T,',')+']';
   End;
  End;
 End;
Begin
 RawJson:=Walk(N);
End;


{ ------------------------------------------------------------------ }
{ Dates                                                               }
{ ------------------------------------------------------------------ }

Function EpochToIso(E:Int64):AnsiString;
Var
 S:AnsiString;
Begin
 S:=StampToStr(E);
 EpochToIso:=Copy(S,1,10)+'T'+Copy(S,12,8)+'Z';
End;

Function IsoToDay(Const S:AnsiString):Int64;
Begin
 IsoToDay:=DaysFromCivil(ToInt(Copy(S,1,4),1970),ToInt(Copy(S,6,2),1),ToInt(Copy(S,9,2),1));
End;

Function DayToIso(D:Int64):AnsiString;
Begin
 DayToIso:=Copy(StampToStr(D*86400),1,10);
End;

{ "2024-05-06T07:08:09.000+0200" -> "2024-05-06 07:08:09" }
Function DateCell(Const Iso:AnsiString):AnsiString;
Begin
 If Length(Iso)<10 Then Begin DateCell:=Iso;Exit;End;
 If Length(Iso)>=19 Then DateCell:=Copy(Iso,1,10)+' '+Copy(Iso,12,8) Else DateCell:=Copy(Iso,1,10);
End;

Const
 DayNames:Array[0..6]of AnsiString=('Thu','Fri','Sat','Sun','Mon','Tue','Wed');
 MonNames:Array[1..12]of AnsiString=('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec');

{ "Thu, 02 May 24" }
Function DateShort(Const Iso:AnsiString):AnsiString;
Var
 Y,M,D:LongInt;
 Z:Int64;
Begin
 DateShort:=Iso;
 If Length(Iso)<10 Then Exit;
 Y:=ToInt(Copy(Iso,1,4),0);M:=ToInt(Copy(Iso,6,2),0);D:=ToInt(Copy(Iso,9,2),0);
 If(Y=0)or(M<1)or(M>12)Then Exit;
 Z:=DaysFromCivil(Y,M,D);
 Z:=((Z mod 7)+7)mod 7;
 DateShort:=DayNames[Z]+', '+Copy('0'+IStr(D),Length(IStr(D)),2)+' '+MonNames[M]+' '+Copy(IStr(Y),3,2);
End;

{ date de depart d'un worklog : "2024-05-06T07:08:09.000+0000" }
Function WorklogDate(Const S:AnsiString):AnsiString;
Var
 T:AnsiString;
Begin
 T:=TrimStr(S);
 If T='' Then Begin WorklogDate:=Copy(EpochToIso(NowEpoch),1,19)+'.000+0000';Exit;End;
 T:=ReplaceAll(T,' ','T');
 If Length(T)=10 Then T:=T+'T00:00:00';
 If Length(T)=16 Then T:=T+':00';
 WorklogDate:=Copy(T,1,19)+'.000+0000';
End;

{ ------------------------------------------------------------------ }
{ Acces a l'API Jira                                                  }
{ ------------------------------------------------------------------ }

Function V2(Const P:AnsiString):AnsiString;
Begin
 V2:='/rest/api/2'+P;
End;

Function Agile(Const P:AnsiString):AnsiString;
Begin
 Agile:='/rest/agile/1.0'+P;
End;

Function ApiUrl(Const Path:AnsiString):AnsiString;
Begin
 If StartsWith(Path,'http://')or StartsWith(Path,'https://')Then ApiUrl:=Path
 Else ApiUrl:=JServer+Path;
End;

Procedure ApiCall(Var R:THttpReq;Const Method,Path,Body:AnsiString);
Begin
 RequireConfig;
 ReqInit(R,Method,ApiUrl(Path),AuthValue);
 If Body<>'' Then Begin
  R.BodyStr:=Body;
  R.Headers:='Content-Type: application/json'#13#10;
 End;
 If DebugOn Then Begin
  WriteLn(StdErr,'> ',Method,' ',R.Url);
  If Body<>'' Then WriteLn(StdErr,'> ',Body);
 End;
 HttpDo(R);
 If DebugOn Then Begin
  WriteLn(StdErr,'< HTTP ',R.Status);
  If R.RespBody<>'' Then WriteLn(StdErr,'< ',R.RespBody);
 End;
End;

Function ApiOk(Var R:THttpReq):Boolean;
Begin
 ApiOk:=(R.Err='')and(R.Status>=200)and(R.Status<300);
End;

Function ReasonOf(S:LongInt):AnsiString;
Begin
 Case S of
  400:ReasonOf:='Bad Request';
  401:ReasonOf:='Unauthorized';
  403:ReasonOf:='Forbidden';
  404:ReasonOf:='Not Found';
  405:ReasonOf:='Method Not Allowed';
  409:ReasonOf:='Conflict';
  429:ReasonOf:='Too Many Requests';
  500:ReasonOf:='Internal Server Error';
  502:ReasonOf:='Bad Gateway';
  503:ReasonOf:='Service Unavailable';
  Else ReasonOf:='HTTP error';
 End;
End;

{ message d'erreur de Jira : errorMessages et errors }
Function ErrText(Var R:THttpReq):AnsiString;
Var
 J,E,C:LongInt;
 Msg:AnsiString;
Begin
 If R.Status=0 Then Begin ErrText:='Error: '+R.Err;Exit;End;
 Msg:='';
 J:=JParse(R.RespBody);
 If J>=0 Then Begin
  E:=JGet(J,'errorMessages');
  If(E>=0)and(JP[E].Kind=JK_ARR)Then Begin
   C:=JP[E].First;
   While C>=0 do Begin Msg:=Msg+#10'  '+JTxt(C);C:=JP[C].Next;End;
  End;
  E:=JGet(J,'errors');
  If(E>=0)and(JP[E].Kind=JK_OBJ)Then Begin
   C:=JP[E].First;
   While C>=0 do Begin Msg:=Msg+#10'  '+JP[C].Key+': '+JTxt(C);C:=JP[C].Next;End;
  End;
  If(Msg='')and(JS(J,'message')<>'')Then Msg:=#10'  '+JS(J,'message');
 End;
 If Msg='' Then Msg:=#10'  '+ReasonOf(R.Status);
 ErrText:='Error: HTTP '+IStr(R.Status)+' ('+R.Url+')'+Msg;
 If R.Status=401 Then ErrText:=ErrText+#10+Lg('Check your login and API token (JIRA_API_TOKEN).',
   'V'+#130+'rifiez votre identifiant et votre jeton d''API (JIRA_API_TOKEN).');
End;

Procedure ApiMust(Var R:THttpReq;Const Method,Path,Body:AnsiString);
Begin
 ApiCall(R,Method,Path,Body);
 If not ApiOk(R)Then Die(ErrText(R));
End;

{ requete obligatoire dont le corps est du JSON : renvoie la racine (-1 si corps vide) }
Function ApiJ(Const Method,Path,Body:AnsiString):LongInt;
Var
 R:THttpReq;
Begin
 ApiMust(R,Method,Path,Body);
 If TrimStr(R.RespBody)='' Then Begin ApiJ:=-1;Exit;End;
 ApiJ:=JParse(R.RespBody);
 If ApiJ<0 Then Die('Error: invalid JSON response from '+R.Url);
End;

{ requete tolerante : renvoie -1 en cas d'echec HTTP }
Function ApiTry(Const Method,Path,Body:AnsiString;Var Status:LongInt):LongInt;
Var
 R:THttpReq;
Begin
 ApiCall(R,Method,Path,Body);
 Status:=R.Status;
 ApiTry:=-1;
 If ApiOk(R)and(TrimStr(R.RespBody)<>'')Then ApiTry:=JParse(R.RespBody);
End;

Function OkMark:AnsiString;
Begin
 OkMark:=#226#156#147;
End;

Function BrowseUrl(Const Key:AnsiString):AnsiString;
Begin
 BrowseUrl:=JServer+'/browse/'+Key;
End;

Procedure OpenWeb(Const Url:AnsiString);
Begin
 If ErrTTY Then WriteLn(StdErr,Lg('Opening ','Ouverture de '),Url);
 OpenBrowser(Url);
End;

{ ------------------------------------------------------------------ }
{ Sortie en grille : tableau, plain, csv                              }
{ ------------------------------------------------------------------ }

Type
 TGrid = Record
  Head:TSList;
  Rows:Array of TSList;
  N:LongInt;
 End;

Var
 GridFmt:LongInt;
 GridDelim:AnsiString;
 GridNoHead,GridNoTrunc:Boolean;

Procedure GridInit(Var G:TGrid;Const Head:TSList);
Var
 I:LongInt;
Begin
 SClear(G.Head);
 For I:=0 to Head.N-1 do SAdd(G.Head,Head.A[I]);
 G.N:=0;
 SetLength(G.Rows,0);
End;

Procedure GridAdd(Var G:TGrid;Const Row:TSList);
Var
 I:LongInt;
Begin
 If G.N>=Length(G.Rows)Then SetLength(G.Rows,Length(G.Rows)*2+16);
 SClear(G.Rows[G.N]);
 For I:=0 to Row.N-1 do SAdd(G.Rows[G.N],ReplaceAll(ReplaceAll(Row.A[I],#13,''),#10,' '));
 Inc(G.N);
End;

Function CsvCell(Const S:AnsiString):AnsiString;
Begin
 If(Pos(',',S)>0)or(Pos('"',S)>0)or(Pos(#10,S)>0)or(Pos(GridDelim,S)>0)Then
   CsvCell:='"'+ReplaceAll(S,'"','""')+'"'
 Else CsvCell:=S;
End;

Procedure GridPrint(Var G:TGrid);
Var
 Cols,I,J,Tot,Big,Sep:LongInt;
 W:Array[0..31]of LongInt;
 Line,Dl:AnsiString;
Begin
 Cols:=G.Head.N;
 If Cols>32 Then Cols:=32;
 Dl:=GridDelim;
 If Dl='' Then Dl:=#9;
 If GridFmt=1 Then Begin
  If not GridNoHead Then Begin
   Line:='';
   For J:=0 to Cols-1 do Begin If J>0 Then Line:=Line+Dl;Line:=Line+G.Head.A[J];End;
   WriteLn(Line);
  End;
  For I:=0 to G.N-1 do Begin
   Line:='';
   For J:=0 to Cols-1 do Begin
    If J>0 Then Line:=Line+Dl;
    If J<G.Rows[I].N Then Line:=Line+G.Rows[I].A[J];
   End;
   WriteLn(Line);
  End;
  Exit;
 End;
 If GridFmt=2 Then Begin
  If Dl=#9 Then Dl:=',';
  If not GridNoHead Then Begin
   Line:='';
   For J:=0 to Cols-1 do Begin If J>0 Then Line:=Line+Dl;Line:=Line+CsvCell(G.Head.A[J]);End;
   WriteLn(Line);
  End;
  For I:=0 to G.N-1 do Begin
   Line:='';
   For J:=0 to Cols-1 do Begin
    If J>0 Then Line:=Line+Dl;
    If J<G.Rows[I].N Then Line:=Line+CsvCell(G.Rows[I].A[J]);
   End;
   WriteLn(Line);
  End;
  Exit;
 End;
 For J:=0 to Cols-1 do Begin
  W[J]:=0;
  If not GridNoHead Then W[J]:=DispLen(G.Head.A[J]);
 End;
 For I:=0 to G.N-1 do
  For J:=0 to Cols-1 do
   If(J<G.Rows[I].N)and(DispLen(G.Rows[I].A[J])>W[J])Then W[J]:=DispLen(G.Rows[I].A[J]);
 If (not GridNoTrunc)and OutTTY Then
  Repeat
   Tot:=(Cols-1)*2;Big:=0;
   For J:=0 to Cols-1 do Begin Inc(Tot,W[J]);If W[J]>W[Big]Then Big:=J;End;
   If(Tot>TermWidth)and(W[Big]>14)Then Begin
    Sep:=Tot-TermWidth;
    If W[Big]-Sep<14 Then W[Big]:=14 Else Dec(W[Big],Sep);
   End
   Else Break;
  Until False;
 If not GridNoHead Then Begin
  Line:='';
  For J:=0 to Cols-1 do Begin
   Line:=Line+PadD(G.Head.A[J],W[J]);
   If J<Cols-1 Then Line:=Line+'  ';
  End;
  WriteLn(TrimRight_(Line));
 End;
 For I:=0 to G.N-1 do Begin
  Line:='';
  For J:=0 to Cols-1 do Begin
   If J<G.Rows[I].N Then Begin
    If GridNoTrunc Then Line:=Line+PadD(G.Rows[I].A[J],W[J])
    Else Line:=Line+PadD(Trunc_(G.Rows[I].A[J],W[J]),W[J]);
   End
   Else Line:=Line+PadD('',W[J]);
   If J<Cols-1 Then Line:=Line+'  ';
  End;
  WriteLn(TrimRight_(Line));
 End;
End;
{ ------------------------------------------------------------------ }
{ Markdown <-> balisage wiki de Jira (description et commentaires)    }
{ ------------------------------------------------------------------ }

Function FindStr(Const S,Sub:AnsiString;From:LongInt):LongInt;
Var
 P:LongInt;
Begin
 If From>Length(S)Then Begin FindStr:=0;Exit;End;
 P:=Pos(Sub,Copy(S,From,Length(S)));
 If P=0 Then FindStr:=0 Else FindStr:=P+From-1;
End;

{ une ligne de Markdown -> balisage Jira }
Function MdInline(Const S:AnsiString):AnsiString;
Var
 I,E,M:LongInt;
 R,Inner,Lbl:AnsiString;
Begin
 R:='';I:=1;
 While I<=Length(S)do Begin
  If S[I]='`' Then Begin
   E:=FindStr(S,'`',I+1);
   If E>0 Then Begin R:=R+'{{'+Copy(S,I+1,E-I-1)+'}}';I:=E+1;Continue;End;
  End;
  If S[I]='[' Then Begin
   E:=FindStr(S,'](',I+1);
   If E>0 Then Begin
    M:=FindStr(S,')',E+2);
    If M>0 Then Begin
     Lbl:=Copy(S,I+1,E-I-1);
     R:=R+'['+Lbl+'|'+Copy(S,E+2,M-E-2)+']';
     I:=M+1;Continue;
    End;
   End;
  End;
  If(Copy(S,I,2)='**')or(Copy(S,I,2)='__')Then Begin
   E:=FindStr(S,Copy(S,I,2),I+2);
   If E>0 Then Begin R:=R+'*'+MdInline(Copy(S,I+2,E-I-2))+'*';I:=E+2;Continue;End;
  End;
  If Copy(S,I,2)='~~' Then Begin
   E:=FindStr(S,'~~',I+2);
   If E>0 Then Begin R:=R+'-'+MdInline(Copy(S,I+2,E-I-2))+'-';I:=E+2;Continue;End;
  End;
  If((S[I]='*')or(S[I]='_'))and(I<Length(S))and(S[I+1]<>' ')and(S[I+1]<>S[I])Then Begin
   E:=FindStr(S,S[I],I+1);
   If(E>I+1)and(S[E-1]<>' ')and((I=1)or(S[I-1]=' '))Then Begin
    R:=R+'_'+MdInline(Copy(S,I+1,E-I-1))+'_';I:=E+1;Continue;
   End;
  End;
  R:=R+S[I];Inc(I);
 End;
 MdInline:=R;
End;

Function MdToJira(Const Md:AnsiString):AnsiString;
Var
 L:TSList;
 I,K,Lv:LongInt;
 B:TBuf;
 Ln,T,Pre:AnsiString;
 InCode:Boolean;
Begin
 BufClear(B);
 SplitStr(ReplaceAll(Md,#13,''),#10,L);
 InCode:=False;
 For I:=0 to L.N-1 do Begin
  Ln:=L.A[I];
  T:=TrimStr(Ln);
  If Copy(T,1,3)='```' Then Begin
   If InCode Then BufAdd(B,'{code}') Else Begin
    If Length(T)>3 Then BufAdd(B,'{code:'+Copy(T,4,Length(T))+'}') Else BufAdd(B,'{code}');
   End;
   InCode:=not InCode;
  End
  Else If InCode Then BufAdd(B,Ln)
  Else Begin
   K:=0;
   While(K<Length(T))and(T[K+1]='#')do Inc(K);
   If(K>0)and(K<=6)and(Length(T)>K)and(T[K+1]=' ')Then
     BufAdd(B,'h'+IStr(K)+'. '+MdInline(Copy(T,K+2,Length(T))))
   Else If(Copy(T,1,2)='- ')or(Copy(T,1,2)='* ')Then Begin
    Lv:=1;
    K:=0;
    While(K<Length(Ln))and(Ln[K+1]=' ')do Inc(K);
    Lv:=K div 2+1;
    BufAdd(B,StringOfChar('*',Lv)+' '+MdInline(Copy(T,3,Length(T))));
   End
   Else If(Length(T)>2)and(T[1]in['0'..'9'])and(Pos('. ',T)>0)and(Pos('. ',T)<=4)Then
     BufAdd(B,'# '+MdInline(Copy(T,Pos('. ',T)+2,Length(T))))
   Else If Copy(T,1,2)='> ' Then BufAdd(B,'bq. '+MdInline(Copy(T,3,Length(T))))
   Else If(T='---')or(T='***')Then BufAdd(B,'----')
   Else BufAdd(B,MdInline(Ln));
  End;
  If I<L.N-1 Then BufAdd(B,#10);
 End;
 MdToJira:=BufStr(B);
End;

{ ligne de balisage Jira -> texte lisible (Markdown) }
Function WikiInline(Const S:AnsiString):AnsiString;
Var
 I,E,P:LongInt;
 R,Inner:AnsiString;
 Function WordStart(K:LongInt):Boolean;
 Begin
  WordStart:=(K=1)or(S[K-1]in[' ','(','[','>',#9]);
 End;
Begin
 R:='';I:=1;
 While I<=Length(S)do Begin
  If Copy(S,I,2)='{{' Then Begin
   E:=FindStr(S,'}}',I+2);
   If E>0 Then Begin R:=R+'`'+Copy(S,I+2,E-I-2)+'`';I:=E+2;Continue;End;
  End;
  If S[I]='[' Then Begin
   E:=FindStr(S,']',I+1);
   If E>0 Then Begin
    Inner:=Copy(S,I+1,E-I-1);
    P:=Pos('|',Inner);
    If P>0 Then R:=R+'['+Copy(Inner,1,P-1)+']('+Copy(Inner,P+1,Length(Inner))+')'
    Else R:=R+'['+Inner+']';
    I:=E+1;Continue;
   End;
  End;
  If(S[I]='*')and WordStart(I)and(I<Length(S))and(S[I+1]<>' ')Then Begin
   E:=FindStr(S,'*',I+1);
   If(E>I+1)and(S[E-1]<>' ')Then Begin R:=R+'**'+WikiInline(Copy(S,I+1,E-I-1))+'**';I:=E+1;Continue;End;
  End;
  If(S[I]='_')and WordStart(I)and(I<Length(S))and(S[I+1]<>' ')Then Begin
   E:=FindStr(S,'_',I+1);
   If(E>I+1)and(S[E-1]<>' ')Then Begin R:=R+'_'+WikiInline(Copy(S,I+1,E-I-1))+'_';I:=E+1;Continue;End;
  End;
  R:=R+S[I];Inc(I);
 End;
 WikiInline:=R;
End;

Function JiraToMd(Const W:AnsiString):AnsiString;
Var
 L:TSList;
 I,K:LongInt;
 B:TBuf;
 Ln:AnsiString;
 InCode:Boolean;
Begin
 BufClear(B);
 SplitStr(ReplaceAll(W,#13,''),#10,L);
 InCode:=False;
 For I:=0 to L.N-1 do Begin
  Ln:=L.A[I];
  If(Copy(Ln,1,6)='{code}')or(Copy(Ln,1,6)='{code:')or(Copy(Ln,1,10)='{noformat}')Then Begin
   If InCode Then BufAdd(B,'```') Else Begin
    If Copy(Ln,1,6)='{code:' Then Begin
     K:=Pos('}',Ln);
     BufAdd(B,'```'+Copy(Ln,7,K-7));
    End
    Else BufAdd(B,'```');
   End;
   InCode:=not InCode;
  End
  Else If InCode Then BufAdd(B,Ln)
  Else If(Length(Ln)>3)and(Ln[1]='h')and(Ln[2]in['1'..'6'])and(Copy(Ln,3,2)='. ')Then
    BufAdd(B,StringOfChar('#',Ord(Ln[2])-48)+' '+WikiInline(Copy(Ln,5,Length(Ln))))
  Else If(Length(Ln)>1)and(Ln[1]='*')and(Pos(' ',Ln)>1)and(Pos(' ',Ln)<=4)and(Copy(Ln,1,Pos(' ',Ln)-1)=StringOfChar('*',Pos(' ',Ln)-1))Then Begin
    K:=Pos(' ',Ln)-1;
    BufAdd(B,StringOfChar(' ',(K-1)*2)+'- '+WikiInline(Copy(Ln,K+2,Length(Ln))));
  End
  Else If(Length(Ln)>1)and(Ln[1]='#')and(Pos(' ',Ln)>1)and(Pos(' ',Ln)<=4)and(Copy(Ln,1,Pos(' ',Ln)-1)=StringOfChar('#',Pos(' ',Ln)-1))Then Begin
    K:=Pos(' ',Ln)-1;
    BufAdd(B,StringOfChar(' ',(K-1)*2)+'1. '+WikiInline(Copy(Ln,K+2,Length(Ln))));
  End
  Else If Copy(Ln,1,4)='bq. ' Then BufAdd(B,'> '+WikiInline(Copy(Ln,5,Length(Ln))))
  Else If Ln='----' Then BufAdd(B,'---')
  Else BufAdd(B,WikiInline(Ln));
  If I<L.N-1 Then BufAdd(B,#10);
 End;
 JiraToMd:=BufStr(B);
End;
{ ------------------------------------------------------------------ }
{ Fonctions communes aux commandes                                    }
{ ------------------------------------------------------------------ }

Type
 TIList = Record
  A:Array of LongInt;
  N:LongInt;
 End;

Procedure IAdd(Var L:TIList;V:LongInt);
Begin
 If L.N>=Length(L.A)Then SetLength(L.A,Length(L.A)*2+16);
 L.A[L.N]:=V;
 Inc(L.N);
End;

Var
 NoInput:Boolean;

Function InteractiveOk:Boolean;
Begin
 InteractiveOk:=InTTY and OutTTY and not NoInput;
End;

Function AskLine(Const Q_,Def:AnsiString):AnsiString;
Var
 S:AnsiString;
Begin
 Write(StdErr,'? ',Q_);
 If Def<>'' Then Write(StdErr,' [',Def,']');
 Write(StdErr,': ');
 S:=TrimStr(ReadLine_);
 If S='' Then S:=Def;
 AskLine:=S;
End;

{ menu numerote ; renvoie l'indice choisi (0-base) }
Function AskSelect(Const Q_:AnsiString;Const Opts:TSList):LongInt;
Var
 I,V:LongInt;
 S:AnsiString;
Begin
 WriteLn(StdErr,'? ',Q_);
 For I:=0 to Opts.N-1 do WriteLn(StdErr,'  ',I+1,'. ',Opts.A[I]);
 Repeat
  Write(StdErr,'> ');
  S:=TrimStr(ReadLine_);
  V:=ToInt(S,0);
  If(S='')and Eof(Input)Then Halt(2);
 Until(V>=1)and(V<=Opts.N);
 AskSelect:=V-1;
End;

Function Confirm(Const Q_:AnsiString;Def:Boolean):Boolean;
Var
 S:AnsiString;
Begin
 Write(StdErr,'? ',Q_,' ');
 If Def Then Write(StdErr,'(Y/n) ') Else Write(StdErr,'(y/N) ');
 S:=LoStr(TrimStr(ReadLine_));
 If S='' Then Confirm:=Def Else Confirm:=(S='y')or(S='yes')or(S='o')or(S='oui');
End;

{ lit plusieurs lignes jusqu'a une ligne vide }
Function AskBody(Const Q_:AnsiString):AnsiString;
Var
 L:AnsiString;
 B:TBuf;
Begin
 WriteLn(StdErr,'? ',Q_,Lg(' (finish with an empty line)',' (terminez par une ligne vide)'));
 BufClear(B);
 Repeat
  L:=ReadLine_;
  If L='' Then Break;
  BufAdd(B,L+#10);
 Until Eof(Input);
 AskBody:=Copy(BufStr(B),1,B.N-1);
End;

{ cle de ticket : "123" devient PROJ-123 ; le reste est mis en majuscules }
Function IssueKey(Const S_:AnsiString):AnsiString;
Var
 S:AnsiString;
 I:LongInt;
 Dig:Boolean;
Begin
 S:=TrimStr(S_);
 If S='' Then Die(Lg('Error: issue key is required','Erreur : la cl'+#130+' du ticket est obligatoire'));
 If Pos('/browse/',S)>0 Then S:=Copy(S,Pos('/browse/',S)+8,Length(S));
 Dig:=True;
 For I:=1 to Length(S)do If not(S[I]in['0'..'9'])Then Dig:=False;
 If Dig Then Begin
  If JProject='' Then Die(Lg('Error: project not set, use a full key such as PROJ-'+S,
    'Erreur : projet non d'+#130+'fini, utilisez une cl'+#130+' compl'+#138+'te comme PROJ-'+S));
  IssueKey:=JProject+'-'+S;
 End
 Else IssueKey:=UpStr(S);
End;

{ liste de noms d'un tableau JSON : [{"name":..}] }
Function NamesOf(A:LongInt;Const Key:AnsiString;Const Sep:AnsiString):AnsiString;
Var
 C:LongInt;
 L:TSList;
Begin
 SClear(L);
 If(A>=0)and(JP[A].Kind=JK_ARR)Then Begin
  C:=JP[A].First;
  While C>=0 do Begin
   If Key='' Then SAdd(L,JTxt(C)) Else SAdd(L,JS(C,Key));
   C:=JP[C].Next;
  End;
 End;
 NamesOf:=JoinList(L,Sep);
End;

Function OrDash(Const S:AnsiString):AnsiString;
Begin
 If S='' Then OrDash:='-' Else OrDash:=S;
End;

{ ------------------------------------------------------------------ }
{ Utilisateurs                                                        }
{ ------------------------------------------------------------------ }

Var
 LastUserName:AnsiString;

{ objet JSON de l'utilisateur pour un champ assignee ; 'null' si Q = x ; '-1' pour defaut }
Function UserObj(Const Q_,Proj:AnsiString):AnsiString;
Var
 Q_s:AnsiString;
 J,C,Pick:LongInt;
 Path,Idf:AnsiString;
Begin
 Q_s:=TrimStr(Q_);
 LastUserName:='';
 If LoStr(Q_s)='x' Then Begin UserObj:='null';Exit;End;
 If LoStr(Q_s)='default' Then Begin
  If IsCloud Then UserObj:='{"accountId":"-1"}' Else UserObj:='{"name":"-1"}';
  LastUserName:='default';
  Exit;
 End;
 If IsCloud Then Path:='/user/assignable/search?query='+UrlEnc(Q_s,False)
 Else Path:='/user/assignable/search?username='+UrlEnc(Q_s,False);
 If Proj<>'' Then Path:=Path+'&project='+UrlEnc(Proj,False);
 J:=ApiJ('GET',V2(Path),'');
 Pick:=-1;
 If(J>=0)and(JP[J].Kind=JK_ARR)Then Begin
  C:=JP[J].First;
  While C>=0 do Begin
   If Pick<0 Then Pick:=C;
   If(LoStr(JS(C,'displayName'))=LoStr(Q_s))or(LoStr(JS(C,'emailAddress'))=LoStr(Q_s))
     or(LoStr(JS(C,'name'))=LoStr(Q_s))Then Begin Pick:=C;Break;End;
   C:=JP[C].Next;
  End;
 End;
 If Pick<0 Then Die(Lg('Error: user not found: ','Erreur : utilisateur introuvable : ')+Q_s);
 LastUserName:=JS(Pick,'displayName');
 If IsCloud Then Idf:='{"accountId":'+JQ(JS(Pick,'accountId'))+'}'
 Else Begin
  If JS(Pick,'name')<>'' Then Idf:='{"name":'+JQ(JS(Pick,'name'))+'}'
  Else Idf:='{"key":'+JQ(JS(Pick,'key'))+'}';
 End;
 UserObj:=Idf;
End;

{ ------------------------------------------------------------------ }
{ Recherche de tickets                                                }
{ ------------------------------------------------------------------ }

Const
 BaseFields='summary,issuetype,status,assignee,reporter,priority,resolution,created,updated,labels,'+
   'components,fixVersions,versions,parent,duedate';

Function SearchFields:AnsiString;
Begin
 SearchFields:=BaseFields;
 If JEpicName<>'' Then SearchFields:=SearchFields+','+JEpicName;
End;

{ recupere les tickets [From, From+Limit) ; Agile=True : endpoint agile (startAt/total) }
Procedure SearchIssues(Const Base,Jql:AnsiString;Agile_:Boolean;From,Limit:LongInt;Var L:TIList;Var Total:LongInt);
Var
 J,C,Seen,Step,StartAt:LongInt;
 Tok,Path:AnsiString;
 Cloud:Boolean;
Begin
 L.N:=0;SetLength(L.A,0);Total:=0;
 Cloud:=IsCloud and not Agile_;
 Seen:=0;Tok:='';
 If not Cloud Then Seen:=From;
 StartAt:=From;
 While L.N<Limit do Begin
  Step:=Limit-L.N;
  If Step>100 Then Step:=100;
  If Step<1 Then Step:=1;
  If Cloud Then Begin
   Path:=Base+'?jql='+UrlEnc(Jql,False)+'&fields='+UrlEnc(SearchFields,False)+'&maxResults=100';
   If Tok<>'' Then Path:=Path+'&nextPageToken='+UrlEnc(Tok,False);
  End
  Else Path:=Base+'?jql='+UrlEnc(Jql,False)+'&fields='+UrlEnc(SearchFields,False)+'&maxResults='+IStr(Step)
    +'&startAt='+IStr(StartAt);
  J:=ApiJ('GET',Path,'');
  If J<0 Then Break;
  C:=JGet(J,'issues');
  If(C<0)or(JP[C].Cnt=0)Then Break;
  C:=JP[C].First;
  While C>=0 do Begin
   If(Seen>=From)and(L.N<Limit)Then IAdd(L,C);
   Inc(Seen);
   C:=JP[C].Next;
  End;
  If(JGet(J,'total')>=0)Then Total:=JI(J,'total');
  If Cloud Then Begin
   Tok:=JS(J,'nextPageToken');
   If Tok='' Then Break;
  End
  Else Begin
   Inc(StartAt,JCnt(JGet(J,'issues')));
   If(Total>0)and(StartAt>=Total)Then Break;
  End;
 End;
 If Total<L.N Then Total:=L.N;
End;

{ ------------------------------------------------------------------ }
{ Construction de la requete JQL a partir des options                 }
{ ------------------------------------------------------------------ }

Function JqlQ(Const S:AnsiString):AnsiString;
Begin
 JqlQ:='"'+ReplaceAll(ReplaceAll(S,'\','\\'),'"','\"')+'"';
End;

{ condition champ = valeur ; ~ devant la valeur nie, x signifie vide }
Function Cond(Const Field,Val_:AnsiString):AnsiString;
Var
 V:AnsiString;
 Neg:Boolean;
Begin
 V:=Val_;Neg:=False;
 If(V<>'')and(V[1]='~')Then Begin Neg:=True;Delete(V,1,1);End;
 If LoStr(V)='x' Then Begin
  If Neg Then Cond:=Field+' IS NOT EMPTY' Else Cond:=Field+' IS EMPTY';
 End
 Else If Neg Then Cond:=Field+' != '+JqlQ(V)
 Else Cond:=Field+' = '+JqlQ(V);
End;

Function CondIn(Const Field:AnsiString;Const Vals:TSList):AnsiString;
Var
 I:LongInt;
 T,Neg:Boolean;
 L:TSList;
 V:AnsiString;
Begin
 If Vals.N=1 Then Begin CondIn:=Cond(Field,Vals.A[0]);Exit;End;
 SClear(L);Neg:=False;
 For I:=0 to Vals.N-1 do Begin
  V:=Vals.A[I];
  If(V<>'')and(V[1]='~')Then Begin Neg:=True;Delete(V,1,1);End;
  SAdd(L,JqlQ(V));
 End;
 If Neg Then CondIn:=Field+' NOT IN ('+JoinList(L,', ')+')' Else CondIn:=Field+' IN ('+JoinList(L,', ')+')';
End;

{ filtre de date : today, week, month, year, AAAA-MM-JJ, -1d }
Function DateCond(Const Field,V_:AnsiString;Const Op:AnsiString):AnsiString;
Var
 V:AnsiString;
 D:Int64;
Begin
 V:=TrimStr(V_);
 DateCond:='';
 If Op<>'=' Then Begin
  If(V<>'')and(V[1]='-')Then DateCond:=Field+' '+Op+' '+V Else DateCond:=Field+' '+Op+' '+JqlQ(V);
  Exit;
 End;
 If V='today' Then DateCond:=Field+' >= startOfDay()'
 Else If V='week' Then DateCond:=Field+' >= startOfWeek()'
 Else If V='month' Then DateCond:=Field+' >= startOfMonth()'
 Else If V='year' Then DateCond:=Field+' >= startOfYear()'
 Else If(V<>'')and(V[1]='-')Then DateCond:=Field+' >= '+V
 Else If Length(V)=10 Then Begin
  D:=IsoToDay(V);
  DateCond:=Field+' >= '+JqlQ(V)+' AND '+Field+' < '+JqlQ(DayToIso(D+1));
 End
 Else DateCond:=Field+' >= '+JqlQ(V);
End;

{ options communes de filtrage des listes }
Procedure OptFilters;
Begin
 Opt('type','t','string','Filter issues by type@@Filtre les tickets par type');
 Opt('resolution','R','string','Filter issues by resolution type@@Filtre les tickets par r'+#130+'solution');
 Opt('status','s','*string','Filter issues by status@@Filtre les tickets par '+#130+'tat');
 Opt('priority','y','string','Filter issues by priority@@Filtre les tickets par priorit'+#130+'');
 Opt('reporter','r','string','Filter issues by reporter (email or display name)@@Filtre les tickets par rapporteur (courriel ou nom)');
 Opt('assignee','a','string','Filter issues by assignee (email or display name)@@Filtre les tickets par personne assign'+#130+'e (courriel ou nom)');
 Opt('component','C','string','Filter issues by component@@Filtre les tickets par composant');
 Opt('label','l','*string','Filter issues by label@@Filtre les tickets par '+#130+'tiquette');
 Opt('parent','P','string','Filter issues by parent@@Filtre les tickets par parent');
 Opt('watching','w','','Issues you are watching@@Tickets que vous suivez');
 Opt('history','i','','Issues you accessed recently@@Tickets consult'+#130+'s r'+#130+'cemment');
 Opt('created','','string','Filter issues by created date (today, week, month, year, yyyy-mm-dd or period like -1d)@@Filtre par date de cr'+#130+'ation (today, week, month, year, aaaa-mm-jj ou p'+#130+'riode comme -1d)');
 Opt('updated','','string','Filter issues by updated date@@Filtre par date de mise '+#133+' jour');
 Opt('created-after','','string','Filter issues created after a date@@Tickets cr'+#130+''+#130+'s apr'+#138+'s une date');
 Opt('created-before','','string','Filter issues created before a date@@Tickets cr'+#130+''+#130+'s avant une date');
 Opt('updated-after','','string','Filter issues updated after a date@@Tickets mis '+#133+' jour apr'+#138+'s une date');
 Opt('updated-before','','string','Filter issues updated before a date@@Tickets mis '+#133+' jour avant une date');
 Opt('jql','q','string','Run this JQL query in the project context@@Ex'+#130+'cute cette requ'+#136+'te JQL dans le contexte du projet');
 Opt('order-by','','string','Field to order the list by (default "created")@@Champ de tri de la liste (d'+#130+'faut : "created")');
 Opt('reverse','','','Reverse the display order (default: DESC)@@Inverse l''ordre d''affichage (d'+#130+'faut : DESC)');
End;

{ assemble le JQL ; Text = texte libre ; ExtraType = type impose ('' si aucun) }
Function BuildJql(Const Text:AnsiString;Const ExtraType:AnsiString):AnsiString;
Var
 Parts,Vals:TSList;
 J,Ord_,U,Up:AnsiString;
 P:LongInt;
 Dir:AnsiString;
 Procedure Add(Const S:AnsiString);
 Begin
  If S<>'' Then SAdd(Parts,S);
 End;
Begin
 SClear(Parts);
 If JProject<>'' Then Add('project = '+JqlQ(JProject));
 If ExtraType<>'' Then Add('issuetype = '+JqlQ(ExtraType))
 Else If OptHas('type')Then Add(Cond('issuetype',OptGet('type')));
 If OptHas('resolution')Then Add(Cond('resolution',OptGet('resolution')));
 OptCsv('status',Vals);
 If Vals.N>0 Then Add(CondIn('status',Vals));
 If OptHas('priority')Then Add(Cond('priority',OptGet('priority')));
 If OptHas('reporter')Then Add(Cond('reporter',OptGet('reporter')));
 If OptHas('assignee')Then Add(Cond('assignee',OptGet('assignee')));
 If OptHas('component')Then Add(Cond('component',OptGet('component')));
 OptCsv('label',Vals);
 If Vals.N>0 Then Add(CondIn('labels',Vals));
 If OptHas('parent')Then Add('parent = '+JqlQ(IssueKey(OptGet('parent'))));
 If OptHas('watching')Then Add('issue IN watchedIssues()');
 If OptHas('history')Then Add('issue IN issueHistory()');
 If OptHas('created')Then Add(DateCond('created',OptGet('created'),'='));
 If OptHas('updated')Then Add(DateCond('updated',OptGet('updated'),'='));
 If OptHas('created-after')Then Add(DateCond('created',OptGet('created-after'),'>'));
 If OptHas('created-before')Then Add(DateCond('created',OptGet('created-before'),'<'));
 If OptHas('updated-after')Then Add(DateCond('updated',OptGet('updated-after'),'>'));
 If OptHas('updated-before')Then Add(DateCond('updated',OptGet('updated-before'),'<'));
 If Text<>'' Then Add('text ~ '+JqlQ(Text));
 Ord_:='';
 If OptHas('jql')Then Begin
  J:=OptGet('jql');
  Up:=UpStr(J);
  P:=Pos('ORDER BY',Up);
  If P>0 Then Begin Ord_:=TrimStr(Copy(J,P+8,Length(J)));J:=TrimStr(Copy(J,1,P-1));End;
  If J<>'' Then Add('('+J+')');
 End;
 If Ord_='' Then Begin
  U:=OptGet('order-by');
  If U='' Then U:='created';
  If OptHas('reverse')Then Dir:='ASC' Else Dir:='DESC';
  Ord_:=U+' '+Dir;
 End;
 If Parts.N=0 Then BuildJql:='ORDER BY '+Ord_
 Else BuildJql:=JoinList(Parts,' AND ')+' ORDER BY '+Ord_;
End;

{ ------------------------------------------------------------------ }
{ Sortie des listes de tickets                                        }
{ ------------------------------------------------------------------ }

Procedure OptListOut(Const DefCols:AnsiString);
Begin
 Opt('plain','','','Display output in plain mode@@Affiche en mode texte');
 Opt('raw','','','Print raw Jira API response@@Affiche la r'+#130+'ponse brute (JSON) de l''API Jira');
 Opt('csv','','','Print output in CSV format@@Affiche au format CSV');
 Opt('table','','','Display output in table view@@Affiche en tableau');
 Opt('columns','','string','Comma separated list of columns to display in the plain mode. Defaults to '+DefCols+'@@Colonnes '+#133+' afficher, s'+#130+'par'+#130+'es par des virgules. D'+#130+'faut : '+DefCols);
 Opt('delimiter','','string','Custom delimiter for plain mode (default "\t")@@S'+#130+'parateur du mode texte (d'+#130+'faut : tabulation)');
 Opt('no-headers','','','Don''t display table headers in plain mode@@N''affiche pas les en-t'+#136+'tes');
 Opt('no-truncate','','','Show all available columns in plain mode, without truncating@@N''abr'+#138+'ge pas les cellules');
 Opt('paginate','','string','Paginate the result. Max 100 at a time, ex: --paginate 20, or --paginate 10:50 (from:limit)@@Pagine le r'+#130+'sultat. Max 100 '+#133+' la fois : --paginate 20 ou --paginate 10:50 (d'+#130+'but:limite)');
End;

Procedure ListFlags;
Begin
 GridFmt:=0;
 If OptHas('plain')Then GridFmt:=1;
 If OptHas('csv')Then GridFmt:=2;
 If OptHas('delimiter')Then GridDelim:=OptGet('delimiter') Else GridDelim:='';
 If GridDelim='\t' Then GridDelim:=#9;
 GridNoHead:=OptHas('no-headers');
 GridNoTrunc:=OptHas('no-truncate');
End;

{ --paginate "debut:limite" ; renvoie les deux valeurs }
Procedure PageArgs(Var From,Limit:LongInt);
Var
 V:AnsiString;
 P:LongInt;
Begin
 From:=0;Limit:=100;
 V:=OptGet('paginate');
 If V='' Then Exit;
 P:=Pos(':',V);
 If P=0 Then Limit:=ToInt(V,100)
 Else Begin From:=ToInt(Copy(V,1,P-1),0);Limit:=ToInt(Copy(V,P+1,Length(V)),100);End;
 If Limit<1 Then Limit:=1;
 If From<0 Then From:=0;
End;

Function IssueCell(N:LongInt;Const Col:AnsiString):AnsiString;
Begin
 IssueCell:='';
 If Col='KEY' Then IssueCell:=JS(N,'key')
 Else If Col='TYPE' Then IssueCell:=JS(N,'fields.issuetype.name')
 Else If Col='SUMMARY' Then IssueCell:=JS(N,'fields.summary')
 Else If Col='NAME' Then Begin
  If(JEpicName<>'')and(JS(N,'fields.'+JEpicName)<>'')Then IssueCell:=JS(N,'fields.'+JEpicName)
  Else IssueCell:=JS(N,'fields.summary');
 End
 Else If Col='STATUS' Then IssueCell:=JS(N,'fields.status.name')
 Else If Col='ASSIGNEE' Then IssueCell:=JS(N,'fields.assignee.displayName')
 Else If Col='REPORTER' Then IssueCell:=JS(N,'fields.reporter.displayName')
 Else If Col='PRIORITY' Then IssueCell:=JS(N,'fields.priority.name')
 Else If Col='RESOLUTION' Then IssueCell:=JS(N,'fields.resolution.name')
 Else If Col='CREATED' Then IssueCell:=DateCell(JS(N,'fields.created'))
 Else If Col='UPDATED' Then IssueCell:=DateCell(JS(N,'fields.updated'))
 Else If Col='LABELS' Then IssueCell:=NamesOf(JPath(N,'fields.labels'),'',',')
 Else If Col='COMPONENTS' Then IssueCell:=NamesOf(JPath(N,'fields.components'),'name',',')
 Else If Col='FIXVERSION' Then IssueCell:=NamesOf(JPath(N,'fields.fixVersions'),'name',',')
 Else If Col='AFFECTSVERSION' Then IssueCell:=NamesOf(JPath(N,'fields.versions'),'name',',')
 Else If Col='PARENT' Then IssueCell:=JS(N,'fields.parent.key')
 Else If Col='DUEDATE' Then IssueCell:=JS(N,'fields.duedate');
End;

Function ValidCol(Const C:AnsiString):Boolean;
Begin
 ValidCol:=(C='KEY')or(C='TYPE')or(C='SUMMARY')or(C='NAME')or(C='STATUS')or(C='ASSIGNEE')or(C='REPORTER')
  or(C='PRIORITY')or(C='RESOLUTION')or(C='CREATED')or(C='UPDATED')or(C='LABELS')or(C='COMPONENTS')
  or(C='FIXVERSION')or(C='AFFECTSVERSION')or(C='PARENT')or(C='DUEDATE');
End;

{ affiche une liste de tickets selon --raw, --csv, --plain ou tableau }
Procedure ShowIssues(Const L:TIList;Const DefCols:AnsiString);
Var
 Cols,Row:TSList;
 G:TGrid;
 I,J:LongInt;
 Cs:AnsiString;
 T:TSList;
 Root:LongInt;
Begin
 If OptHas('raw')Then Begin
  SClear(T);
  For I:=0 to L.N-1 do SAdd(T,RawJson(L.A[I]));
  Root:=JParse('['+JoinList(T,',')+']');
  JPrint(Root);
  Exit;
 End;
 ListFlags;
 Cs:=OptGet('columns');
 If Cs='' Then Cs:=DefCols;
 SplitStr(UpStr(Cs),',',Cols);
 SClear(T);
 For I:=0 to Cols.N-1 do Begin
  Cols.A[I]:=TrimStr(Cols.A[I]);
  If not ValidCol(Cols.A[I])Then Die(Lg('Error: invalid column: ','Erreur : colonne invalide : ')+Cols.A[I]);
 End;
 GridInit(G,Cols);
 For I:=0 to L.N-1 do Begin
  SClear(Row);
  For J:=0 to Cols.N-1 do SAdd(Row,IssueCell(L.A[I],Cols.A[J]));
  GridAdd(G,Row);
 End;
 GridPrint(G);
End;

Const
 DefIssueCols='TYPE,KEY,SUMMARY,STATUS,ASSIGNEE,REPORTER,PRIORITY,RESOLUTION,CREATED,UPDATED,LABELS';

Procedure NoResults;
Begin
 If ErrTTY Then WriteLn(StdErr,Lg('No result found for given query in project "','Aucun r'+#130+'sultat pour la requ'+#136+'te dans le projet "'),JProject,'"');
End;
{ ------------------------------------------------------------------ }
{ jira issue : list, view, create, edit, ...                          }
{ ------------------------------------------------------------------ }

Var
 FieldsNode:LongInt = -2;

{ liste des champs Jira (/field), chargee une seule fois }
Function AllFields:LongInt;
Begin
 If FieldsNode=-2 Then FieldsNode:=ApiJ('GET',V2('/field'),'');
 AllFields:=FieldsNode;
End;

{ ajoute un champ personnalise "cle=valeur" a la liste de champs }
Procedure AddCustom(Var F:TSList;Const KV:AnsiString);
Var
 P,C,Fd:LongInt;
 Key,Val_,Id,Ty,It:AnsiString;
 Items:TSList;
 I:LongInt;
 Arr:TSList;
Begin
 P:=Pos('=',KV);
 If P=0 Then Die(Lg('Error: invalid custom field "','Erreur : champ personnalis'+#130+' invalide "')+KV+'" (key=value)');
 Key:=TrimStr(Copy(KV,1,P-1));Val_:=Copy(KV,P+1,Length(KV));
 Fd:=-1;
 C:=JP[AllFields].First;
 While C>=0 do Begin
  If(JS(C,'id')=Key)or(LoStr(JS(C,'name'))=LoStr(Key))Then Begin Fd:=C;Break;End;
  C:=JP[C].Next;
 End;
 If Fd<0 Then Die(Lg('Error: unknown field "','Erreur : champ inconnu "')+Key+'"');
 Id:=JS(Fd,'id');
 Ty:=JS(Fd,'schema.type');
 It:=JS(Fd,'schema.items');
 If(Ty='number')and(ToInt(Val_,-999999999)<>-999999999)Then FR(F,Id,Val_)
 Else If Ty='number' Then FR(F,Id,Val_)
 Else If Ty='option' Then FR(F,Id,'{"value":'+JQ(Val_)+'}')
 Else If Ty='user' Then FR(F,Id,UserObj(Val_,JProject))
 Else If Ty='array' Then Begin
  SplitStr(Val_,',',Items);
  SClear(Arr);
  For I:=0 to Items.N-1 do Begin
   If It='string' Then SAdd(Arr,JQ(TrimStr(Items.A[I])))
   Else If It='option' Then SAdd(Arr,'{"value":'+JQ(TrimStr(Items.A[I]))+'}')
   Else SAdd(Arr,'{"name":'+JQ(TrimStr(Items.A[I]))+'}');
  End;
  FR(F,Id,'['+JoinList(Arr,',')+']');
 End
 Else FS(F,Id,Val_);
End;

{ corps du ticket : --body ou --template (- pour stdin) }
Function BodyArg(Var Given:Boolean):AnsiString;
Var
 F,S:AnsiString;
Begin
 Given:=False;BodyArg:='';
 If OptHas('body')Then Begin Given:=True;BodyArg:=OptGet('body');End
 Else If OptHas('template')Then Begin
  Given:=True;
  F:=OptGet('template');
  If F='-' Then BodyArg:=ReplaceAll(ReadStdin,#13,'')
  Else If ReadAll(F,S)Then BodyArg:=ReplaceAll(S,#13,'')
  Else Die(Lg('Error: unable to read template file: ','Erreur : lecture du mod'+#138+'le impossible : ')+F);
 End;
End;

{ options des champs partagees par create, edit et clone }
Procedure OptTicketFields(WithType:Boolean);
Begin
 If WithType Then Opt('type','t','string','Issue type@@Type de ticket');
 Opt('summary','s','string','Issue summary or title@@R'+#130+'sum'+#130+' ou titre du ticket');
 Opt('body','b','string','Issue description@@Description du ticket');
 Opt('priority','y','string','Set issue priority@@Priorit'+#130+' du ticket');
 Opt('label','l','*string','Add issue labels (prefix with - to remove, edit only)@@'+#144+'tiquettes du ticket (pr'+#130+'fixe - pour retirer, en modification)');
 Opt('component','C','*string','Add issue components (prefix with - to remove, edit only)@@Composants du ticket (pr'+#130+'fixe - pour retirer, en modification)');
 Opt('fix-version','','*string','Add fix version (prefix with - to remove, edit only)@@Version de correction (pr'+#130+'fixe - pour retirer, en modification)');
 Opt('affects-version','','*string','Add affects version (prefix with - to remove, edit only)@@Version affect'+#130+'e (pr'+#130+'fixe - pour retirer, en modification)');
 Opt('parent','P','string','Link to a parent key@@Cl'+#130+' du ticket parent');
 Opt('custom','','*string','Set custom fields, format: key=value@@Champs personnalis'+#130+'s, format : cl'+#130+'=valeur');
 Opt('template','T','string','Path to a file to read the description from (use "-" for standard input)@@Fichier contenant la description ('+#174+' - '+#175+' pour l''entr'+#130+'e standard)');
 Opt('no-input','','','Disable prompt for non-required fields@@D'+#130+'sactive les questions interactives');
End;

Function NameList(Const Vals:TSList):AnsiString;
Var
 I:LongInt;
 T:TSList;
Begin
 SClear(T);
 For I:=0 to Vals.N-1 do SAdd(T,'{"name":'+JQ(Vals.A[I])+'}');
 NameList:='['+JoinList(T,',')+']';
End;

{ ajoute (ou retire, si prefixe -) des valeurs a un champ de type liste dans update }
Procedure ListOps(Var Upd:TSList;Const Field,Opt_:AnsiString;Named:Boolean);
Var
 Vals,Ops:TSList;
 I:LongInt;
 V:AnsiString;
Begin
 OptCsv(Opt_,Vals);
 If Vals.N=0 Then Exit;
 SClear(Ops);
 For I:=0 to Vals.N-1 do Begin
  V:=Vals.A[I];
  If(V<>'')and(V[1]='-')Then Begin
   Delete(V,1,1);
   If Named Then SAdd(Ops,'{"remove":{"name":'+JQ(V)+'}}') Else SAdd(Ops,'{"remove":'+JQ(V)+'}');
  End
  Else Begin
   If Named Then SAdd(Ops,'{"add":{"name":'+JQ(V)+'}}') Else SAdd(Ops,'{"add":'+JQ(V)+'}');
  End;
 End;
 FR(Upd,Field,'['+JoinList(Ops,',')+']');
End;

Function IssueTypes(Const Proj:AnsiString;Var L:TSList):Boolean;
Var
 J,C:LongInt;
Begin
 SClear(L);
 J:=ApiJ('GET',V2('/project/'+UrlEnc(Proj,False)),'');
 C:=JGet(J,'issueTypes');
 If(C>=0)and(JP[C].Kind=JK_ARR)Then Begin
  C:=JP[C].First;
  While C>=0 do Begin SAdd(L,JS(C,'name'));C:=JP[C].Next;End;
 End;
 IssueTypes:=L.N>0;
End;

Procedure CmdIssueList;
Var
 L:TIList;
 Total,From,Limit:LongInt;
 Jql,Text:AnsiString;
 I:LongInt;
Begin
 CmdBegin('issue list','');
 CmdAlias('lists');CmdAlias('ls');
 CmdExample('  # List all issues in the project'#10'  jira issue list'#10#10'  # List bugs that are open'#10'  jira issue list -tBug -sOpen'#10#10'  # List unassigned issues'#10'  jira issue list -ax'#10#10'  # Run a custom JQL'#10'  jira issue list -q "created > -7d ORDER BY created DESC"');
 OptFilters;OptListOut(DefIssueCols);OptG;
 ParseArgs(ArgStart);
 ApplyGlobals;
 RequireConfig;
 If not OptHas('jql')Then NeedProject;
 Text:='';
 For I:=0 to PosArgs.N-1 do Text:=Text+IfThen_(I>0,' ','')+PosArgs.A[I];
 Jql:=BuildJql(Text,'');
 PageArgs(From,Limit);
 If IsCloud Then SearchIssues(V2('/search/jql'),Jql,False,From,Limit,L,Total)
 Else SearchIssues(V2('/search'),Jql,False,From,Limit,L,Total);
 If L.N=0 Then Begin NoResults;Exit;End;
 ShowIssues(L,DefIssueCols);
End;

Function StatusEmoji(Const St:AnsiString):AnsiString;
Var
 S:AnsiString;
Begin
 S:=LoStr(St);
 If(Pos('done',S)>0)or(Pos('closed',S)>0)or(Pos('resolved',S)>0)Then StatusEmoji:=''+#226+#156+#133+''
 Else If(Pos('progress',S)>0)Then StatusEmoji:=''+#240+#159+#154+#167+''
 Else StatusEmoji:=''+#240+#159+#148+#150+'';
End;

Procedure CmdIssueView;
Var
 J,C,Cm,Cn,Nc,I,Start:LongInt;
 Key,Desc,Ln:AnsiString;
 Wch:LongInt;
Begin
 CmdBegin('issue view','ISSUE-KEY');
 CmdAlias('show');
 CmdExample('  # View details of an issue'#10'  jira issue view ISSUE-1'#10#10'  # Show 5 recent comments'#10'  jira issue view ISSUE-1 --comments 5');
 Opt('comments','','uint','Show N comments (default 1)@@Affiche N commentaires (d'+#130+'faut : 1)');
 Opt('plain','','','Display output in plain mode@@Affiche en mode texte');
 Opt('raw','','','Print raw Jira API response@@Affiche la r'+#130+'ponse brute (JSON) de l''API Jira');
 OptG;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 ApplyGlobals;
 RequireConfig;
 Key:=IssueKey(Pos1(0));
 J:=ApiJ('GET',V2('/issue/'+Key+'?fields=*all'),'');
 If OptHas('raw')Then Begin JPrint(J);Exit;End;
 Wch:=0;
 If JPath(J,'fields.watches.watchCount')>=0 Then Wch:=JI(J,'fields.watches.watchCount');
 Cm:=JPath(J,'fields.comment.comments');
 Nc:=JCnt(Cm);
 Ln:=StatusEmoji(JS(J,'fields.status.name'))+' '+JS(J,'fields.status.name')+'  '+#240+#159+#144+#158+' '+JS(J,'fields.issuetype.name')
   +'  '+#226+#140+#155+' '+DateShort(JS(J,'fields.updated'));
 If JS(J,'fields.assignee.displayName')<>'' Then Ln:=Ln+'  '+#240+#159+#145+#183+' '+JS(J,'fields.assignee.displayName')
 Else Ln:=Ln+'  '+#240+#159+#145+#183+' '+Lg('Unassigned','Non assign'+#130+'');
 Ln:=Ln+'  '+#240+#159+#148+#145+' '+JS(J,'key')+'  '+#240+#159+#146+#173+' '+IStr(Nc)+Lg(' comment(s)',' commentaire(s)');
 If JS(J,'fields.priority.name')<>'' Then Ln:=Ln+'  '+#240+#159+#154+#128+' '+JS(J,'fields.priority.name');
 If JCnt(JPath(J,'fields.components'))>0 Then Ln:=Ln+'  '+#240+#159+#147+#166+' '+NamesOf(JPath(J,'fields.components'),'name',', ');
 If JCnt(JPath(J,'fields.labels'))>0 Then Ln:=Ln+'  '+#240+#159+#143+#183+''+#239+#184+#143+'  '+NamesOf(JPath(J,'fields.labels'),'',', ');
 Ln:=Ln+'  '+#240+#159+#145+#128+' '+IStr(Wch)+Lg(' watchers',' observateurs');
 WriteLn(Ln);
 WriteLn;
 WriteLn('# ',JS(J,'fields.summary'));
 WriteLn;
 WriteLn(Lg('Reporter: ','Rapporteur : '),OrDash(JS(J,'fields.reporter.displayName')),
   Lg('   Created: ','   Cr'+#130+''+#130+' : '),DateCell(JS(J,'fields.created')));
 If JS(J,'fields.parent.key')<>'' Then
   WriteLn(Lg('Parent:   ','Parent :     '),JS(J,'fields.parent.key'),'  ',JS(J,'fields.parent.fields.summary'));
 If JS(J,'fields.resolution.name')<>'' Then WriteLn(Lg('Resolution: ','R'+#130+'solution : '),JS(J,'fields.resolution.name'));
 If JS(J,'fields.duedate')<>'' Then WriteLn(Lg('Due: ',''+#144+'ch'+#130+'ance : '),JS(J,'fields.duedate'));
 If JCnt(JPath(J,'fields.fixVersions'))>0 Then WriteLn(Lg('Fix versions: ','Versions de correction : '),NamesOf(JPath(J,'fields.fixVersions'),'name',', '));
 WriteLn;
 Desc:=JS(J,'fields.description');
 If Desc<>'' Then Begin WriteLn(JiraToMd(Desc));WriteLn;End
 Else WriteLn(Lg('No description provided.','Aucune description.'));
 C:=JPath(J,'fields.subtasks');
 If JCnt(C)>0 Then Begin
  WriteLn(Lg('Subtasks','Sous-t'+#131+'ches'));
  C:=JP[C].First;
  While C>=0 do Begin WriteLn('  ',JS(C,'key'),'  ',JS(C,'fields.summary'),'  [',JS(C,'fields.status.name'),']');C:=JP[C].Next;End;
  WriteLn;
 End;
 C:=JPath(J,'fields.issuelinks');
 If JCnt(C)>0 Then Begin
  WriteLn(Lg('Linked issues','Tickets li'+#130+'s'));
  C:=JP[C].First;
  While C>=0 do Begin
   If JGet(C,'outwardIssue')>=0 Then
     WriteLn('  ',JS(C,'type.outward'),' ',JS(C,'outwardIssue.key'),'  ',JS(C,'outwardIssue.fields.summary'))
   Else WriteLn('  ',JS(C,'type.inward'),' ',JS(C,'inwardIssue.key'),'  ',JS(C,'inwardIssue.fields.summary'));
   C:=JP[C].Next;
  End;
  WriteLn;
 End;
 Cn:=OptInt('comments',1);
 If(Cn>0)and(Nc>0)Then Begin
  WriteLn('------------------------ ',Lg('Comments','Commentaires'),' ------------------------');
  Start:=Nc-Cn;
  If Start<0 Then Start:=0;
  I:=0;
  C:=JP[Cm].First;
  While C>=0 do Begin
   If I>=Start Then Begin
    WriteLn(JS(C,'author.displayName'),' '+#226+#128+#162+' ',DateCell(JS(C,'created')));
    WriteLn;
    WriteLn(JiraToMd(JS(C,'body')));
    WriteLn;
   End;
   Inc(I);
   C:=JP[C].Next;
  End;
 End;
End;

Procedure CmdIssueCreate;
Var
 F,Upd,Lst:TSList;
 Given:Boolean;
 Body_,Ty,Sm,Pr,U,Proj:AnsiString;
 R:THttpReq;
 J,Idx:LongInt;
 Types:TSList;
 I:LongInt;
Begin
 CmdBegin('issue create','');
 CmdAlias('new');
 CmdExample('  # Create issue in the configured project'#10'  jira issue create'#10#10'  # Create a bug without prompts'#10'  jira issue create -tBug -s"Erreur de compilation" -yHigh -b"Le compilateur plante" --no-input');
 OptTicketFields(True);
 Opt('assignee','a','string','Assign issue to a user@@Assigne le ticket '+#133+' un utilisateur');
 Opt('reporter','r','string','Report issue on behalf of a user@@Rapporte le ticket au nom d''un utilisateur');
 Opt('original-estimate','e','string','Set original estimate for the issue (e.g. 2d 3h)@@Estimation initiale (ex. : 2d 3h)');
 Opt('web','w','','Open issue in a web browser after creation@@Ouvre le ticket dans le navigateur apr'+#138+'s sa cr'+#130+'ation');
 Opt('raw','','','Print output in JSON format@@Affiche le r'+#130+'sultat en JSON');
 OptG;
 ParseArgs(ArgStart);
 ApplyGlobals;
 NoInput:=OptHas('no-input');
 RequireConfig;
 Proj:=NeedProject;
 Body_:=BodyArg(Given);
 Ty:=OptGet('type');Sm:=OptGet('summary');Pr:=OptGet('priority');
 If((Ty='')or(Sm=''))and InteractiveOk Then Begin
  If Ty='' Then Begin
   If IssueTypes(Proj,Types)Then Ty:=Types.A[AskSelect(Lg('Issue type','Type de ticket'),Types)]
   Else Ty:=AskLine(Lg('Issue type','Type de ticket'),'');
  End;
  If Sm='' Then Sm:=AskLine(Lg('Summary','R'+#130+'sum'+#130+''),'');
  If not Given Then Body_:=AskBody(Lg('Description','Description'));
  If(Pr='')Then Pr:=AskLine(Lg('Priority (optional)','Priorit'+#130+' (facultatif)'),'');
 End;
 If(Ty='')or(Sm='')Then Die(Lg('Error: issue type and summary are required (-t, -s)',
   'Erreur : le type et le r'+#130+'sum'+#130+' du ticket sont obligatoires (-t, -s)'));
 SClear(F);SClear(Upd);
 FR(F,'project','{"key":'+JQ(Proj)+'}');
 FR(F,'issuetype','{"name":'+JQ(Ty)+'}');
 FS(F,'summary',Sm);
 If Body_<>'' Then FS(F,'description',MdToJira(Body_));
 If Pr<>'' Then FR(F,'priority','{"name":'+JQ(Pr)+'}');
 OptCsv('label',Lst);
 If Lst.N>0 Then FR(F,'labels',StrArr(Lst));
 OptCsv('component',Lst);
 If Lst.N>0 Then FR(F,'components',NameList(Lst));
 OptCsv('fix-version',Lst);
 If Lst.N>0 Then FR(F,'fixVersions',NameList(Lst));
 OptCsv('affects-version',Lst);
 If Lst.N>0 Then FR(F,'versions',NameList(Lst));
 If OptHas('parent')Then FR(F,'parent','{"key":'+JQ(IssueKey(OptGet('parent')))+'}');
 If OptHas('assignee')Then Begin
  U:=UserObj(OptGet('assignee'),Proj);
  If U<>'null' Then FR(F,'assignee',U);
 End;
 If OptHas('reporter')Then Begin
  U:=UserObj(OptGet('reporter'),Proj);
  If U<>'null' Then FR(F,'reporter',U);
 End;
 If OptHas('original-estimate')Then FR(F,'timetracking','{"originalEstimate":'+JQ(OptGet('original-estimate'))+'}');
 OptList('custom',Lst);
 For I:=0 to Lst.N-1 do AddCustom(F,Lst.A[I]);
 ApiMust(R,'POST',V2('/issue'),'{"fields":'+ObjOf(F)+'}');
 If OptHas('raw')Then Begin WriteLn(R.RespBody);Exit;End;
 J:=JParse(R.RespBody);
 WriteLn(OkMark,' ',Lg('Issue created','Ticket cr'+#130+''+#130+''));
 WriteLn(BrowseUrl(JS(J,'key')));
 If OptHas('web')Then OpenWeb(BrowseUrl(JS(J,'key')));
End;

Procedure CmdIssueEdit;
Var
 F,Upd,Lst:TSList;
 Given:Boolean;
 Body_,Sm,Pr,Key:AnsiString;
 J:LongInt;
 R:THttpReq;
 Changed:Boolean;
 I:LongInt;
Begin
 CmdBegin('issue edit','ISSUE-KEY');
 CmdAlias('modify');
 CmdExample('  # Edit summary and priority'#10'  jira issue edit ISSUE-1 -s"New summary" -yHigh --no-input'#10#10'  # Add a label and remove another one'#10'  jira issue edit ISSUE-1 -lbackend -l-frontend --no-input');
 OptTicketFields(False);
 OptG;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 ApplyGlobals;
 NoInput:=OptHas('no-input');
 RequireConfig;
 Key:=IssueKey(Pos1(0));
 Body_:=BodyArg(Given);
 Sm:=OptGet('summary');Pr:=OptGet('priority');
 Changed:=(Sm<>'')or Given or(Pr<>'')or OptHas('label')or OptHas('component')or OptHas('fix-version')
   or OptHas('affects-version')or OptHas('parent')or OptHas('custom');
 If not Changed Then Begin
  If not InteractiveOk Then Die(Lg('Error: nothing to update, provide at least one field flag',
    'Erreur : rien '+#133+' modifier, indiquez au moins un champ'));
  J:=ApiJ('GET',V2('/issue/'+Key+'?fields=summary,description,priority'),'');
  Sm:=AskLine(Lg('Summary','R'+#130+'sum'+#130+''),JS(J,'fields.summary'));
  Body_:=AskBody(Lg('Description (empty line to keep current)','Description (ligne vide pour conserver)'));
  Given:=Body_<>'';
  Pr:=AskLine(Lg('Priority','Priorit'+#130+''),JS(J,'fields.priority.name'));
 End;
 SClear(F);SClear(Upd);
 If Sm<>'' Then FS(F,'summary',Sm);
 If Given Then FS(F,'description',MdToJira(Body_));
 If Pr<>'' Then FR(F,'priority','{"name":'+JQ(Pr)+'}');
 If OptHas('parent')Then FR(F,'parent','{"key":'+JQ(IssueKey(OptGet('parent')))+'}');
 ListOps(Upd,'labels','label',False);
 ListOps(Upd,'components','component',True);
 ListOps(Upd,'fixVersions','fix-version',True);
 ListOps(Upd,'versions','affects-version',True);
 OptList('custom',Lst);
 For I:=0 to Lst.N-1 do AddCustom(F,Lst.A[I]);
 If(F.N=0)and(Upd.N=0)Then Die(Lg('Error: nothing to update','Erreur : rien '+#133+' modifier'));
 Body_:='{';
 If F.N>0 Then Body_:=Body_+'"fields":'+ObjOf(F);
 If Upd.N>0 Then Body_:=Body_+IfThen_(F.N>0,',','')+'"update":'+ObjOf(Upd);
 Body_:=Body_+'}';
 ApiMust(R,'PUT',V2('/issue/'+Key),Body_);
 WriteLn(OkMark,' ',Lg('Issue updated','Ticket mis '+#133+' jour'));
 WriteLn(BrowseUrl(Key));
End;

Procedure CmdIssueMove;
Var
 Key,State,Cm,Res,Id,Nm,To_,Avail:AnsiString;
 J,C:LongInt;
 F,Upd,Names:TSList;
 R:THttpReq;
 Body_,U:AnsiString;
 Hit:Boolean;
Begin
 CmdBegin('issue move','ISSUE-KEY STATE');
 CmdAlias('transition');CmdAlias('mv');
 CmdExample('  # Move to "In Progress"'#10'  jira issue move ISSUE-1 "In Progress"'#10#10'  # Move to Done with a comment and a resolution'#10'  jira issue move ISSUE-1 Done "Fixed" -RFixed');
 Opt('comment','','string','Add comment to the issue@@Ajoute un commentaire au ticket');
 Opt('assignee','a','string','Assign issue to a user@@Assigne le ticket '+#133+' un utilisateur');
 Opt('resolution','R','string','Set resolution@@D'+#130+'finit la r'+#130+'solution');
 Opt('web','w','','Open issue in a web browser after transition@@Ouvre le ticket dans le navigateur apr'+#138+'s la transition');
 OptG;
 ParseArgs(ArgStart);
 NeedArgs(1,3);
 ApplyGlobals;
 RequireConfig;
 Key:=IssueKey(Pos1(0));
 State:=Pos1(1);
 Cm:=OptGet('comment');
 If(Cm='')and(PosArgs.N>2)Then Cm:=Pos1(2);
 J:=ApiJ('GET',V2('/issue/'+Key+'/transitions'),'');
 C:=JGet(J,'transitions');
 SClear(Names);
 Id:='';To_:='';
 If(C>=0)and(JP[C].Kind=JK_ARR)Then Begin
  C:=JP[C].First;
  While C>=0 do Begin
   SAdd(Names,JS(C,'name'));
   If(State<>'')and(Id='')and((LoStr(JS(C,'name'))=LoStr(State))or(LoStr(JS(C,'to.name'))=LoStr(State))
     or(JS(C,'id')=State))Then Begin Id:=JS(C,'id');To_:=JS(C,'to.name');If To_='' Then To_:=JS(C,'name');End;
   C:=JP[C].Next;
  End;
 End;
 If(State='')Then Begin
  If not InteractiveOk Then Die(Lg('Error: target state is required','Erreur : l'''+#130+'tat cible est obligatoire'));
  If Names.N=0 Then Die(Lg('Error: no transition available','Erreur : aucune transition disponible'));
  Nm:=Names.A[AskSelect(Lg('Transition to','Transition vers'),Names)];
  C:=JP[JGet(J,'transitions')].First;
  While C>=0 do Begin
   If JS(C,'name')=Nm Then Begin Id:=JS(C,'id');To_:=JS(C,'to.name');If To_='' Then To_:=Nm;Break;End;
   C:=JP[C].Next;
  End;
 End;
 If Id='' Then Begin
  Avail:='';
  For C:=0 to Names.N-1 do Avail:=Avail+IfThen_(C>0,', ','')+''''+Names.A[C]+'''';
  WriteLn(StdErr,Lg('Error: invalid transition state "','Erreur : '+#130+'tat de transition invalide "'),State,'"');
  WriteLn(StdErr,Lg('Available states for issue ',''+#144+'tats disponibles pour le ticket '),Key,': ',Avail);
  Halt(1);
 End;
 SClear(F);SClear(Upd);
 Res:=OptGet('resolution');
 If Res<>'' Then FR(F,'resolution','{"name":'+JQ(Res)+'}');
 If OptHas('assignee')Then Begin
  U:=UserObj(OptGet('assignee'),JProject);
  If U='null' Then Begin
   If IsCloud Then U:='{"accountId":null}' Else U:='{"name":null}';
  End;
  FR(F,'assignee',U);
 End;
 If Cm<>'' Then FR(Upd,'comment','[{"add":{"body":'+JQ(MdToJira(Cm))+'}}]');
 Body_:='{"transition":{"id":'+JQ(Id)+'}';
 If F.N>0 Then Body_:=Body_+',"fields":'+ObjOf(F);
 If Upd.N>0 Then Body_:=Body_+',"update":'+ObjOf(Upd);
 Body_:=Body_+'}';
 ApiMust(R,'POST',V2('/issue/'+Key+'/transitions'),Body_);
 WriteLn(OkMark,' ',Lg('Issue "','Ticket "'),Key,Lg('" status changed to "','" : '+#130+'tat chang'+#130+' en "'),To_,'"');
 WriteLn(BrowseUrl(Key));
 If OptHas('web')Then OpenWeb(BrowseUrl(Key));
End;

Procedure CmdIssueAssign;
Var
 Key,Who,U:AnsiString;
 R:THttpReq;
Begin
 CmdBegin('issue assign','ISSUE-KEY ASSIGNEE');
 CmdAlias('asg');
 CmdExample('  # Assign to a user (name or email)'#10'  jira issue assign ISSUE-1 "Jane Doe"'#10#10'  # Assign to the default assignee'#10'  jira issue assign ISSUE-1 default'#10#10'  # Unassign'#10'  jira issue assign ISSUE-1 x');
 OptG;
 ParseArgs(ArgStart);
 NeedArgs(1,2);
 ApplyGlobals;
 RequireConfig;
 Key:=IssueKey(Pos1(0));
 Who:=Pos1(1);
 If Who='' Then Begin
  If InTTY Then Who:=AskLine(Lg('Assign to (name, email, x to unassign, default)','Assigner '+#133+' (nom, courriel, x pour d'+#130+'sassigner, default)'),'')
  Else Die(Lg('Error: assignee is required','Erreur : la personne assign'+#130+'e est obligatoire'));
  If Who='' Then Die(Lg('Error: assignee is required','Erreur : la personne assign'+#130+'e est obligatoire'));
 End;
 U:=UserObj(Who,JProject);
 If U='null' Then Begin
  If IsCloud Then U:='{"accountId":null}' Else U:='{"name":null}';
 End;
 ApiMust(R,'PUT',V2('/issue/'+Key+'/assignee'),U);
 If LoStr(Who)='x' Then WriteLn(OkMark,' ',Lg('Issue unassigned','Ticket d'+#130+'sassign'+#130+''))
 Else If LoStr(Who)='default' Then WriteLn(OkMark,' ',Lg('Issue assigned to the default assignee','Ticket assign'+#130+' '+#133+' la personne par d'+#130+'faut'))
 Else WriteLn(OkMark,' ',Lg('Issue assigned to ','Ticket assign'+#130+' '+#133+' '),LastUserName);
End;

Procedure CmdIssueCommentAdd;
Var
 Key,Body_,S:AnsiString;
 Given:Boolean;
 R:THttpReq;
Begin
 CmdBegin('issue comment add','ISSUE-KEY [COMMENT_BODY]');
 CmdExample('  # Add comment to an issue'#10'  jira issue comment add ISSUE-1 "My comment"'#10#10'  # Read the comment from a file'#10'  jira issue comment add ISSUE-1 --template /path/to/file.md');
 Opt('template','T','string','Path to a file to read comment body from (use "-" for standard input)@@Fichier contenant le commentaire ('+#174+' - '+#175+' pour l''entr'+#130+'e standard)');
 Opt('web','w','','Open issue in a web browser after adding comment@@Ouvre le ticket dans le navigateur apr'+#138+'s l''ajout');
 Opt('no-input','','','Disable prompt for non-required fields@@D'+#130+'sactive les questions interactives');
 OptG;
 ParseArgs(ArgStart);
 NeedArgs(1,2);
 ApplyGlobals;
 NoInput:=OptHas('no-input');
 RequireConfig;
 Key:=IssueKey(Pos1(0));
 Body_:=Pos1(1);
 If Body_='' Then Body_:=BodyArg(Given);
 If Body_='-' Then Body_:=ReplaceAll(ReadStdin,#13,'');
 If(Body_='')and InteractiveOk Then Body_:=AskBody(Lg('Comment body','Texte du commentaire'));
 If TrimStr(Body_)='' Then Die(Lg('Error: comment body is required','Erreur : le texte du commentaire est obligatoire'));
 ApiMust(R,'POST',V2('/issue/'+Key+'/comment'),'{"body":'+JQ(MdToJira(Body_))+'}');
 WriteLn(OkMark,' ',Lg('Comment added to issue "','Commentaire ajout'+#130+' au ticket "'),Key,'"');
 WriteLn(BrowseUrl(Key));
 If OptHas('web')Then OpenWeb(BrowseUrl(Key));
End;

Procedure CmdIssueDelete;
Var
 Key:AnsiString;
 R:THttpReq;
Begin
 CmdBegin('issue delete','ISSUE-KEY');
 CmdAlias('remove');CmdAlias('rm');CmdAlias('del');
 CmdExample('  # Delete an issue'#10'  jira issue delete ISSUE-1'#10#10'  # Delete an issue along with its subtasks'#10'  jira issue delete ISSUE-1 --cascade');
 Opt('cascade','','','Delete issue along with its subtasks@@Supprime le ticket avec ses sous-t'+#131+'ches');
 OptG;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 ApplyGlobals;
 RequireConfig;
 Key:=IssueKey(Pos1(0));
 ApiMust(R,'DELETE',V2('/issue/'+Key+'?deleteSubtasks='+IfThen_(OptHas('cascade'),'true','false')),'');
 WriteLn(OkMark,' ',Lg('Issue ','Ticket '),Key,Lg(' deleted',' supprim'+#130+''));
End;

Procedure LinkTypesHelp;
Var
 J,C:LongInt;
 L:TSList;
Begin
 J:=ApiJ('GET',V2('/issueLinkType'),'');
 C:=JGet(J,'issueLinkTypes');
 SClear(L);
 If C>=0 Then Begin
  C:=JP[C].First;
  While C>=0 do Begin SAdd(L,JS(C,'name'));C:=JP[C].Next;End;
 End;
 WriteLn(StdErr,Lg('Available link types: ','Types de lien disponibles : '),JoinList(L,', '));
End;

Procedure CmdIssueLink;
Var
 A,B,Ty:AnsiString;
 R:THttpReq;
Begin
 CmdBegin('issue link','INWARD_ISSUE_KEY OUTWARD_ISSUE_KEY ISSUE_LINK_TYPE');
 CmdExample('  # Link ISSUE-1 and ISSUE-2 with the "Blocks" link type'#10'  jira issue link ISSUE-1 ISSUE-2 Blocks');
 OptG;
 ParseArgs(ArgStart);
 NeedArgs(3,3);
 ApplyGlobals;
 RequireConfig;
 A:=IssueKey(Pos1(0));B:=IssueKey(Pos1(1));Ty:=Pos1(2);
 ApiCall(R,'POST',V2('/issueLink'),'{"type":{"name":'+JQ(Ty)+'},"inwardIssue":{"key":'+JQ(A)+'},"outwardIssue":{"key":'+JQ(B)+'}}');
 If not ApiOk(R)Then Begin
  WriteLn(StdErr,ErrText(R));
  LinkTypesHelp;
  Halt(1);
 End;
 WriteLn(OkMark,' ',Lg('Issues linked','Tickets li'+#130+'s'),': ',A,' <-> ',B,' (',Ty,')');
End;

Procedure CmdIssueLinkRemote;
Var
 Key,Url,Title:AnsiString;
 R:THttpReq;
Begin
 CmdBegin('issue link remote','ISSUE-KEY REMOTE_URL [REMOTE_URL_TITLE]');
 CmdExample('  # Add a remote link to an issue'#10'  jira issue link remote ISSUE-1 https://example.com "Example site"');
 OptG;
 ParseArgs(ArgStart);
 NeedArgs(2,3);
 ApplyGlobals;
 RequireConfig;
 Key:=IssueKey(Pos1(0));Url:=Pos1(1);Title:=Pos1(2);
 If Title='' Then Title:=Url;
 ApiMust(R,'POST',V2('/issue/'+Key+'/remotelink'),'{"object":{"url":'+JQ(Url)+',"title":'+JQ(Title)+'}}');
 WriteLn(OkMark,' ',Lg('Remote link added to ','Lien distant ajout'+#130+' '+#133+' '),Key);
End;

Procedure CmdIssueUnlink;
Var
 A,B:AnsiString;
 J,C:LongInt;
 Id:AnsiString;
 R:THttpReq;
Begin
 CmdBegin('issue unlink','INWARD_ISSUE_KEY OUTWARD_ISSUE_KEY');
 CmdExample('  # Unlink ISSUE-1 and ISSUE-2'#10'  jira issue unlink ISSUE-1 ISSUE-2');
 OptG;
 ParseArgs(ArgStart);
 NeedArgs(2,2);
 ApplyGlobals;
 RequireConfig;
 A:=IssueKey(Pos1(0));B:=IssueKey(Pos1(1));
 J:=ApiJ('GET',V2('/issue/'+A+'?fields=issuelinks'),'');
 Id:='';
 C:=JPath(J,'fields.issuelinks');
 If C>=0 Then Begin
  C:=JP[C].First;
  While C>=0 do Begin
   If(JS(C,'outwardIssue.key')=B)or(JS(C,'inwardIssue.key')=B)Then Begin Id:=JS(C,'id');Break;End;
   C:=JP[C].Next;
  End;
 End;
 If Id='' Then Die(Lg('Error: no link found between ','Erreur : aucun lien entre ')+A+' / '+B);
 ApiMust(R,'DELETE',V2('/issueLink/'+Id),'');
 WriteLn(OkMark,' ',Lg('Link removed','Lien supprim'+#130+''));
End;

Procedure CmdIssueClone;
Var
 Key,Sm,Desc,Rep,Find,Repl,Pr,NewKey:AnsiString;
 J,Idx,I:LongInt;
 F,Lst:TSList;
 R:THttpReq;
 U:AnsiString;
Begin
 CmdBegin('issue clone','ISSUE-KEY');
 CmdExample('  # Clone an issue'#10'  jira issue clone ISSUE-1'#10#10'  # Clone and override summary, replacing a word in the text'#10'  jira issue clone ISSUE-1 -s"New summary" -H"old:new"');
 Opt('summary','s','string','Issue summary or title (default: "CLONE - <summary>")@@R'+#130+'sum'+#130+' du clone (d'+#130+'faut : '+#174+' CLONE - <r'+#130+'sum'+#130+'> '+#175+')');
 Opt('priority','y','string','Set issue priority@@Priorit'+#130+' du clone');
 Opt('assignee','a','string','Assign issue to a user@@Assigne le clone '+#133+' un utilisateur');
 Opt('label','l','*string','Add issue labels@@'+#144+'tiquettes du clone');
 Opt('component','C','*string','Replace components@@Composants du clone');
 Opt('parent','P','string','Link to a parent key@@Cl'+#130+' du ticket parent');
 Opt('replace','H','string','Replace string in summary and description during cloning (format "find:replace")@@Remplace du texte dans le r'+#130+'sum'+#130+' et la description (format '+#174+' chercher:remplacer '+#175+')');
 OptG;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 ApplyGlobals;
 RequireConfig;
 Key:=IssueKey(Pos1(0));
 J:=ApiJ('GET',V2('/issue/'+Key+'?fields=summary,description,issuetype,priority,labels,components,fixVersions,versions,parent,project'),'');
 Sm:=OptGet('summary');
 If Sm='' Then Sm:='CLONE - '+JS(J,'fields.summary');
 Desc:=JS(J,'fields.description');
 Rep:=OptGet('replace');
 If Rep<>'' Then Begin
  I:=Pos(':',Rep);
  If I=0 Then Die(Lg('Error: invalid --replace value, expected "find:replace"','Erreur : valeur de --replace invalide, attendu '+#174+' chercher:remplacer '+#175+''));
  Find:=Copy(Rep,1,I-1);Repl:=Copy(Rep,I+1,Length(Rep));
  If Find<>'' Then Begin Sm:=ReplaceAll(Sm,Find,Repl);Desc:=ReplaceAll(Desc,Find,Repl);End;
 End;
 SClear(F);
 FR(F,'project','{"key":'+JQ(IfThen_(JS(J,'fields.project.key')<>'',JS(J,'fields.project.key'),JProject))+'}');
 FR(F,'issuetype','{"name":'+JQ(JS(J,'fields.issuetype.name'))+'}');
 FS(F,'summary',Sm);
 If Desc<>'' Then FS(F,'description',Desc);
 Pr:=OptGet('priority');
 If Pr='' Then Pr:=JS(J,'fields.priority.name');
 If Pr<>'' Then FR(F,'priority','{"name":'+JQ(Pr)+'}');
 OptCsv('label',Lst);
 If Lst.N>0 Then FR(F,'labels',StrArr(Lst))
 Else If JCnt(JPath(J,'fields.labels'))>0 Then FR(F,'labels',RawJson(JPath(J,'fields.labels')));
 OptCsv('component',Lst);
 If Lst.N>0 Then FR(F,'components',NameList(Lst))
 Else If JCnt(JPath(J,'fields.components'))>0 Then Begin
  SClear(Lst);
  Idx:=JP[JPath(J,'fields.components')].First;
  While Idx>=0 do Begin SAdd(Lst,JS(Idx,'name'));Idx:=JP[Idx].Next;End;
  FR(F,'components',NameList(Lst));
 End;
 If OptHas('parent')Then FR(F,'parent','{"key":'+JQ(IssueKey(OptGet('parent')))+'}')
 Else If JS(J,'fields.parent.key')<>'' Then FR(F,'parent','{"key":'+JQ(JS(J,'fields.parent.key'))+'}');
 If OptHas('assignee')Then Begin
  U:=UserObj(OptGet('assignee'),JS(J,'fields.project.key'));
  If U<>'null' Then FR(F,'assignee',U);
 End;
 ApiMust(R,'POST',V2('/issue'),'{"fields":'+ObjOf(F)+'}');
 NewKey:=JS(JParse(R.RespBody),'key');
 ApiCall(R,'POST',V2('/issueLink'),'{"type":{"name":"Cloners"},"inwardIssue":{"key":'+JQ(NewKey)+'},"outwardIssue":{"key":'+JQ(Key)+'}}');
 WriteLn(OkMark,' ',Lg('Issue cloned','Ticket clon'+#130+''));
 WriteLn(BrowseUrl(NewKey));
End;

Procedure CmdWorklogAdd;
Var
 Key,Ts,Cm,Path:AnsiString;
 F:TSList;
 R:THttpReq;
Begin
 CmdBegin('issue worklog add','ISSUE-KEY TIME_SPENT');
 CmdExample('  # Add 2 hours and 30 minutes of work'#10'  jira issue worklog add ISSUE-1 "2h 30m" --no-input'#10#10'  # With a comment and a start date'#10'  jira issue worklog add ISSUE-1 "1d" --comment "Review" --started "2024-05-06 09:00"');
 Opt('comment','','string','Comment about the work@@Commentaire sur le travail effectu'+#130+'');
 Opt('started','','string','The datetime on which the worklog effort was started, format "yyyy-mm-dd hh:mm"@@Date et heure de d'+#130+'but, format '+#174+' aaaa-mm-jj hh:mm '+#175+'');
 Opt('new-estimate','','string','New estimate for the issue@@Nouvelle estimation du ticket');
 Opt('no-input','','','Disable prompt for non-required fields@@D'+#130+'sactive les questions interactives');
 OptG;
 ParseArgs(ArgStart);
 NeedArgs(1,2);
 ApplyGlobals;
 NoInput:=OptHas('no-input');
 RequireConfig;
 Key:=IssueKey(Pos1(0));
 Ts:=Pos1(1);
 If(Ts='')and InteractiveOk Then Ts:=AskLine(Lg('Time spent (e.g. 2h 30m)','Temps pass'+#130+' (ex. : 2h 30m)'),'');
 If Ts='' Then Die(Lg('Error: time spent is required','Erreur : le temps pass'+#130+' est obligatoire'));
 Cm:=OptGet('comment');
 SClear(F);
 FS(F,'timeSpent',Ts);
 FS(F,'started',WorklogDate(OptGet('started')));
 If Cm<>'' Then FS(F,'comment',Cm);
 Path:=V2('/issue/'+Key+'/worklog');
 If OptHas('new-estimate')Then Path:=Path+'?adjustEstimate=new&newEstimate='+UrlEnc(OptGet('new-estimate'),False);
 ApiMust(R,'POST',Path,ObjOf(F));
 WriteLn(OkMark,' ',Lg('Worklog added','Temps de travail ajout'+#130+''));
End;
{ ------------------------------------------------------------------ }
{ project, board, sprint, epic, release, me, open, init, ...          }
{ ------------------------------------------------------------------ }

Procedure OptBasicOut;
Begin
 Opt('plain','','','Display output in plain mode@@Affiche en mode texte');
 Opt('raw','','','Print raw Jira API response@@Affiche la r'+#130+'ponse brute (JSON) de l''API Jira');
 Opt('csv','','','Print output in CSV format@@Affiche au format CSV');
 Opt('table','','','Display output in table view@@Affiche en tableau');
 Opt('delimiter','','string','Custom delimiter for plain mode (default "\t")@@S'+#130+'parateur du mode texte (d'+#130+'faut : tabulation)');
 Opt('no-headers','','','Don''t display table headers in plain mode@@N''affiche pas les en-t'+#136+'tes');
 Opt('no-truncate','','','Show all available columns in plain mode, without truncating@@N''abr'+#138+'ge pas les cellules');
End;

{ affiche les elements d'un tableau JSON en colonnes ; Paths = chemins JSON separes par des virgules }
Procedure ShowTable(Arr:LongInt;Const Heads,Paths:AnsiString);
Var
 H,P,Row:TSList;
 G:TGrid;
 C,J:LongInt;
 V:AnsiString;
Begin
 If OptHas('raw')Then Begin JPrint(Arr);Exit;End;
 ListFlags;
 SplitStr(Heads,',',H);SplitStr(Paths,',',P);
 GridInit(G,H);
 If(Arr>=0)and(JP[Arr].Kind=JK_ARR)Then Begin
  C:=JP[Arr].First;
  While C>=0 do Begin
   SClear(Row);
   For J:=0 to P.N-1 do Begin
    V:=JS(C,P.A[J]);
    If(Length(V)>=19)and(V[5]='-')and(V[11]='T')Then V:=DateCell(V);
    SAdd(Row,V);
   End;
   GridAdd(G,Row);
   C:=JP[C].Next;
  End;
 End;
 GridPrint(G);
End;

Procedure CmdProjectList;
Var
 J:LongInt;
Begin
 CmdBegin('project list','');
 CmdAlias('lists');CmdAlias('ls');
 CmdExample('  jira project list'#10'  jira project list --plain --no-headers');
 OptBasicOut;OptG;
 ParseArgs(ArgStart);
 ApplyGlobals;
 RequireConfig;
 J:=ApiJ('GET',V2('/project?expand=lead'),'');
 ShowTable(J,'KEY,NAME,TYPE,LEAD','key,name,projectTypeKey,lead.displayName');
End;

{ tableaux d'un projet : pagine /board }
Function BoardsOf(Const Proj,Typ:AnsiString):LongInt;
Var
 J,C,Start,Page:LongInt;
 Path:AnsiString;
 Items:TSList;
 Last:Boolean;
Begin
 SClear(Items);
 Start:=0;
 Repeat
  Path:=Agile('/board?startAt='+IStr(Start)+'&maxResults=50');
  If Proj<>'' Then Path:=Path+'&projectKeyOrId='+UrlEnc(Proj,False);
  If Typ<>'' Then Path:=Path+'&type='+Typ;
  J:=ApiJ('GET',Path,'');
  C:=JGet(J,'values');
  Page:=JCnt(C);
  If Page>0 Then Begin
   C:=JP[C].First;
   While C>=0 do Begin SAdd(Items,RawJson(C));C:=JP[C].Next;End;
  End;
  Last:=(Page=0)or(JGet(J,'isLast')<0)or JB(J,'isLast');
  Inc(Start,Page);
 Until Last;
 BoardsOf:=JParse('['+JoinList(Items,',')+']');
End;

Procedure CmdBoardList;
Var
 J:LongInt;
Begin
 CmdBegin('board list','');
 CmdAlias('lists');CmdAlias('ls');
 CmdExample('  jira board list'#10'  jira board list -p PROJ --plain');
 OptBasicOut;OptG;
 ParseArgs(ArgStart);
 ApplyGlobals;
 RequireConfig;
 J:=BoardsOf(JProject,'');
 ShowTable(J,'ID,NAME,TYPE','id,name,type');
End;

Procedure CmdReleaseList;
Var
 J:LongInt;
 Proj:AnsiString;
Begin
 CmdBegin('release list','');
 CmdAlias('lists');CmdAlias('ls');
 CmdExample('  jira release list'#10'  jira release list -p PROJ --plain');
 OptBasicOut;OptG;
 ParseArgs(ArgStart);
 ApplyGlobals;
 RequireConfig;
 Proj:=NeedProject;
 J:=ApiJ('GET',V2('/project/'+UrlEnc(Proj,False)+'/versions'),'');
 ShowTable(J,'ID,NAME,RELEASED,DATE,DESCRIPTION','id,name,released,releaseDate,description');
End;

{ tableau de la configuration, sinon le premier tableau scrum du projet }
Function BoardIdFor:AnsiString;
Var
 J,C:LongInt;
Begin
 BoardIdFor:=JBoardId;
 If JBoardId<>'' Then Exit;
 J:=BoardsOf(NeedProject,'scrum');
 C:=JAt(J,0);
 If C<0 Then Die(Lg('Error: no scrum board found for project ','Erreur : aucun tableau scrum pour le projet ')+JProject);
 BoardIdFor:=JS(C,'id');
End;

{ sprints du tableau, ordre de l'API (du plus ancien au plus recent) ; renvoie un tableau JSON }
Function SprintsOf(Const Board,State:AnsiString):LongInt;
Var
 J,C,Start,Page:LongInt;
 Path:AnsiString;
 Items:TSList;
 Last:Boolean;
Begin
 SClear(Items);
 Start:=0;
 Repeat
  Path:=Agile('/board/'+Board+'/sprint?startAt='+IStr(Start)+'&maxResults=50');
  If State<>'' Then Path:=Path+'&state='+State;
  J:=ApiJ('GET',Path,'');
  C:=JGet(J,'values');
  Page:=JCnt(C);
  If Page>0 Then Begin
   C:=JP[C].First;
   While C>=0 do Begin SAdd(Items,RawJson(C));C:=JP[C].Next;End;
  End;
  Last:=(Page=0)or(JGet(J,'isLast')<0)or JB(J,'isLast');
  Inc(Start,Page);
 Until Last;
 SprintsOf:=JParse('['+JoinList(Items,',')+']');
End;

Procedure CmdSprintList;
Var
 Board,St,Id,Text,Jql:AnsiString;
 Arr,C,Pick,I,From,Limit,Total:LongInt;
 Rev:TSList;
 L:TIList;
 Issues:Boolean;
Begin
 CmdBegin('sprint list','[SPRINT_ID]');
 CmdAlias('lists');CmdAlias('ls');
 CmdExample('  # List all sprints'#10'  jira sprint list'#10#10'  # List issues of the current sprint'#10'  jira sprint list --current'#10#10'  # List issues of a sprint, only bugs assigned to me'#10'  jira sprint list 42 -tBug -a"$(jira me)"');
 Opt('current','','','List issues in the current sprint@@Liste les tickets du sprint actif');
 Opt('prev','','','List issues in the previous sprint@@Liste les tickets du sprint pr'+#130+'c'+#130+'dent');
 Opt('next','','','List issues in the next planned sprint@@Liste les tickets du prochain sprint');
 Opt('state','','string','Filter sprint by its state (comma separated): future, active, closed@@Filtre les sprints par '+#130+'tat (s'+#130+'par'+#130+'s par des virgules) : future, active, closed');
 OptFilters;OptListOut('TYPE,KEY,SUMMARY,STATUS,ASSIGNEE,REPORTER,PRIORITY,RESOLUTION,CREATED,UPDATED,LABELS');OptG;
 ParseArgs(ArgStart);
 ApplyGlobals;
 RequireConfig;
 Board:=BoardIdFor;
 Id:=Pos1(0);
 Issues:=(Id<>'')or OptHas('current')or OptHas('prev')or OptHas('next');
 If not Issues Then Begin
  St:=OptGet('state');
  Arr:=SprintsOf(Board,St);
  { du plus recent au plus ancien }
  SClear(Rev);
  If JCnt(Arr)>0 Then Begin
   C:=JP[Arr].First;
   While C>=0 do Begin SAdd(Rev,RawJson(C));C:=JP[C].Next;End;
  End;
  Text:='';
  For I:=Rev.N-1 downto 0 do Text:=Text+IfThen_(Text<>'',',','')+Rev.A[I];
  Arr:=JParse('['+Text+']');
  ShowTable(Arr,'ID,NAME,START,END,COMPLETE,STATE','id,name,startDate,endDate,completeDate,state');
  Exit;
 End;
 If Id='' Then Begin
  If OptHas('current')Then Arr:=SprintsOf(Board,'active')
  Else If OptHas('prev')Then Arr:=SprintsOf(Board,'closed')
  Else Arr:=SprintsOf(Board,'future');
  If JCnt(Arr)=0 Then Die(Lg('Error: no matching sprint found','Erreur : aucun sprint correspondant'));
  If OptHas('prev')Then Pick:=JP[Arr].Last Else Pick:=JP[Arr].First;
  Id:=JS(Pick,'id');
 End;
 Text:='';
 For I:=1 to PosArgs.N-1 do Text:=Text+IfThen_(I>1,' ','')+PosArgs.A[I];
 Jql:=BuildJql(Text,'');
 PageArgs(From,Limit);
 SearchIssues(Agile('/sprint/'+Id+'/issue'),Jql,True,From,Limit,L,Total);
 If L.N=0 Then Begin NoResults;Exit;End;
 ShowIssues(L,DefIssueCols);
End;

Procedure CmdSprintAdd;
Var
 Id:AnsiString;
 I:LongInt;
 Keys:TSList;
 R:THttpReq;
Begin
 CmdBegin('sprint add','SPRINT_ID ISSUE_1 [ISSUE_2...]');
 CmdExample('  # Add issues to a sprint'#10'  jira sprint add 42 ISSUE-1 ISSUE-2');
 OptG;
 ParseArgs(ArgStart);
 NeedArgs(2,-1);
 ApplyGlobals;
 RequireConfig;
 If PosArgs.N>51 Then Die(Lg('Error: at most 50 issues can be added at once','Erreur : 50 tickets au maximum '+#133+' la fois'));
 Id:=Pos1(0);
 SClear(Keys);
 For I:=1 to PosArgs.N-1 do SAdd(Keys,IssueKey(PosArgs.A[I]));
 ApiMust(R,'POST',Agile('/sprint/'+Id+'/issue'),'{"issues":'+StrArr(Keys)+'}');
 WriteLn(OkMark,' ',Lg('Issues added to the sprint ','Tickets ajout'+#130+'s au sprint '),Id);
End;

Procedure CmdSprintClose;
Var
 Id:AnsiString;
 R:THttpReq;
Begin
 CmdBegin('sprint close','SPRINT_ID');
 CmdExample('  # Close a sprint'#10'  jira sprint close 42');
 OptG;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 ApplyGlobals;
 RequireConfig;
 Id:=Pos1(0);
 ApiMust(R,'POST',Agile('/sprint/'+Id),'{"state":"closed"}');
 WriteLn(OkMark,' ',Lg('Sprint ','Sprint '),Id,Lg(' closed',' clos'));
End;

{ requete JQL pour les tickets d'un epic }
Function EpicJql(Const Key:AnsiString):AnsiString;
Begin
 If JProjType='next-gen' Then EpicJql:='parent = '+JqlQ(Key) Else EpicJql:='"Epic Link" = '+JqlQ(Key);
End;

Procedure CmdEpicList;
Var
 L:TIList;
 Total,From,Limit:LongInt;
 Jql,Text,Key,Base:AnsiString;
 I:LongInt;
Begin
 CmdBegin('epic list','[EPIC-KEY]');
 CmdAlias('lists');CmdAlias('ls');
 CmdExample('  # List all epics'#10'  jira epic list'#10#10'  # List issues in an epic'#10'  jira epic list EPIC-1 -ax');
 OptFilters;OptListOut('KEY,NAME,STATUS,ASSIGNEE,REPORTER,PRIORITY,RESOLUTION,CREATED,UPDATED,LABELS');OptG;
 ParseArgs(ArgStart);
 ApplyGlobals;
 RequireConfig;
 NeedProject;
 PageArgs(From,Limit);
 Key:='';
 If PosArgs.N>0 Then Key:=IssueKey(PosArgs.A[0]);
 If Key='' Then Jql:=BuildJql('','Epic')
 Else Begin
  Text:='';
  For I:=1 to PosArgs.N-1 do Text:=Text+IfThen_(I>1,' ','')+PosArgs.A[I];
  Jql:=BuildJql(Text,'');
  I:=Pos(' ORDER BY ',Jql);
  If I=0 Then Jql:=EpicJql(Key)+' '+Jql Else Jql:=Copy(Jql,1,I-1)+' AND '+EpicJql(Key)+Copy(Jql,I,Length(Jql));
 End;
 If IsCloud Then SearchIssues(V2('/search/jql'),Jql,False,From,Limit,L,Total)
 Else SearchIssues(V2('/search'),Jql,False,From,Limit,L,Total);
 If L.N=0 Then Begin NoResults;Exit;End;
 If Key='' Then ShowIssues(L,'KEY,NAME,STATUS,ASSIGNEE,REPORTER,PRIORITY,RESOLUTION,CREATED,UPDATED,LABELS')
 Else ShowIssues(L,DefIssueCols);
End;

{ identifiant du champ "Epic Name" (config, sinon recherche) }
Function EpicNameField:AnsiString;
Var
 C:LongInt;
Begin
 EpicNameField:=JEpicName;
 If JEpicName<>'' Then Exit;
 C:=JP[AllFields].First;
 While C>=0 do Begin
  If LoStr(JS(C,'name'))='epic name' Then Begin EpicNameField:=JS(C,'id');Exit;End;
  C:=JP[C].Next;
 End;
End;

Procedure CmdEpicCreate;
Var
 F,Lst:TSList;
 Given:Boolean;
 Body_,Sm,Nm,Pr,Proj,Fld,U:AnsiString;
 R:THttpReq;
 J,I:LongInt;
Begin
 CmdBegin('epic create','');
 CmdAlias('new');
 CmdExample('  # Create an epic'#10'  jira epic create -n"Payments" -s"Payments revamp" -b"Rework the payment flow" --no-input');
 Opt('name','n','string','Epic name@@Nom de l''epic');
 OptTicketFields(False);
 Opt('assignee','a','string','Assign epic to a user@@Assigne l''epic '+#133+' un utilisateur');
 Opt('web','w','','Open epic in a web browser after creation@@Ouvre l''epic dans le navigateur apr'+#138+'s sa cr'+#130+'ation');
 Opt('raw','','','Print output in JSON format@@Affiche le r'+#130+'sultat en JSON');
 OptG;
 ParseArgs(ArgStart);
 ApplyGlobals;
 NoInput:=OptHas('no-input');
 RequireConfig;
 Proj:=NeedProject;
 Body_:=BodyArg(Given);
 Nm:=OptGet('name');Sm:=OptGet('summary');Pr:=OptGet('priority');
 If((Nm='')or(Sm=''))and InteractiveOk Then Begin
  If Nm='' Then Nm:=AskLine(Lg('Epic name','Nom de l''epic'),'');
  If Sm='' Then Sm:=AskLine(Lg('Summary','R'+#130+'sum'+#130+''),Nm);
  If not Given Then Body_:=AskBody(Lg('Description','Description'));
 End;
 If Sm='' Then Sm:=Nm;
 If Nm='' Then Nm:=Sm;
 If Sm='' Then Die(Lg('Error: epic name and summary are required (-n, -s)','Erreur : le nom et le r'+#130+'sum'+#130+' de l''epic sont obligatoires (-n, -s)'));
 SClear(F);
 FR(F,'project','{"key":'+JQ(Proj)+'}');
 FR(F,'issuetype','{"name":"Epic"}');
 FS(F,'summary',Sm);
 If JProjType<>'next-gen' Then Begin
  Fld:=EpicNameField;
  If Fld<>'' Then FS(F,Fld,Nm);
 End;
 If Body_<>'' Then FS(F,'description',MdToJira(Body_));
 If Pr<>'' Then FR(F,'priority','{"name":'+JQ(Pr)+'}');
 OptCsv('label',Lst);
 If Lst.N>0 Then FR(F,'labels',StrArr(Lst));
 OptCsv('component',Lst);
 If Lst.N>0 Then FR(F,'components',NameList(Lst));
 OptCsv('fix-version',Lst);
 If Lst.N>0 Then FR(F,'fixVersions',NameList(Lst));
 If OptHas('assignee')Then Begin
  U:=UserObj(OptGet('assignee'),Proj);
  If U<>'null' Then FR(F,'assignee',U);
 End;
 OptList('custom',Lst);
 For I:=0 to Lst.N-1 do AddCustom(F,Lst.A[I]);
 ApiMust(R,'POST',V2('/issue'),'{"fields":'+ObjOf(F)+'}');
 If OptHas('raw')Then Begin WriteLn(R.RespBody);Exit;End;
 J:=JParse(R.RespBody);
 WriteLn(OkMark,' ',Lg('Epic created','Epic cr'+#130+''+#130+''));
 WriteLn(BrowseUrl(JS(J,'key')));
 If OptHas('web')Then OpenWeb(BrowseUrl(JS(J,'key')));
End;

Procedure CmdEpicAdd;
Var
 Epic:AnsiString;
 I:LongInt;
 Keys:TSList;
 R:THttpReq;
Begin
 CmdBegin('epic add','EPIC_KEY ISSUE_1 [ISSUE_2...]');
 CmdExample('  # Add issues to an epic'#10'  jira epic add EPIC-1 ISSUE-1 ISSUE-2');
 OptG;
 ParseArgs(ArgStart);
 NeedArgs(2,-1);
 ApplyGlobals;
 RequireConfig;
 If PosArgs.N>51 Then Die(Lg('Error: at most 50 issues can be added at once','Erreur : 50 tickets au maximum '+#133+' la fois'));
 Epic:=IssueKey(Pos1(0));
 SClear(Keys);
 For I:=1 to PosArgs.N-1 do SAdd(Keys,IssueKey(PosArgs.A[I]));
 If JProjType='next-gen' Then Begin
  For I:=0 to Keys.N-1 do
   ApiMust(R,'PUT',V2('/issue/'+Keys.A[I]),'{"fields":{"parent":{"key":'+JQ(Epic)+'}}}');
 End
 Else ApiMust(R,'POST',Agile('/epic/'+Epic+'/issue'),'{"issues":'+StrArr(Keys)+'}');
 WriteLn(OkMark,' ',Lg('Issues added to the epic ','Tickets ajout'+#130+'s '+#133+' l''epic '),Epic);
End;

Procedure CmdEpicRemove;
Var
 I:LongInt;
 Keys:TSList;
 R:THttpReq;
Begin
 CmdBegin('epic remove','ISSUE_1 [ISSUE_2...]');
 CmdAlias('rm');
 CmdExample('  # Remove issues from their epic'#10'  jira epic remove ISSUE-1 ISSUE-2');
 OptG;
 ParseArgs(ArgStart);
 NeedArgs(1,-1);
 ApplyGlobals;
 RequireConfig;
 If PosArgs.N>50 Then Die(Lg('Error: at most 50 issues can be removed at once','Erreur : 50 tickets au maximum '+#133+' la fois'));
 SClear(Keys);
 For I:=0 to PosArgs.N-1 do SAdd(Keys,IssueKey(PosArgs.A[I]));
 If JProjType='next-gen' Then Begin
  For I:=0 to Keys.N-1 do
   ApiMust(R,'PUT',V2('/issue/'+Keys.A[I]),'{"fields":{"parent":null}}');
 End
 Else ApiMust(R,'POST',Agile('/epic/none/issue'),'{"issues":'+StrArr(Keys)+'}');
 WriteLn(OkMark,' ',Lg('Issues removed from their epic','Tickets retir'+#130+'s de leur epic'));
End;

Procedure CmdMe;
Var
 J:LongInt;
 V:AnsiString;
Begin
 CmdBegin('me','');
 CmdExample('  jira me');
 OptG;
 ParseArgs(ArgStart);
 ApplyGlobals;
 V:=JLogin;
 If V='' Then Begin
  RequireConfig;
  J:=ApiJ('GET',V2('/myself'),'');
  V:=JS(J,'emailAddress');
  If V='' Then V:=JS(J,'name');
 End;
 WriteLn(V);
End;

Procedure CmdOpen;
Var
 Url:AnsiString;
Begin
 CmdBegin('open','[ISSUE_KEY]');
 CmdAlias('browse');
 CmdExample('  # Open the project in the browser'#10'  jira open'#10#10'  # Open an issue'#10'  jira open ISSUE-1'#10#10'  # Print the URL only'#10'  jira open ISSUE-1 --no-browser');
 Opt('no-browser','n','','Do not open the browser, print the URL@@N''ouvre pas le navigateur, affiche l''URL');
 OptG;
 ParseArgs(ArgStart);
 NeedArgs(0,1);
 ApplyGlobals;
 RequireConfig;
 If PosArgs.N>0 Then Url:=BrowseUrl(IssueKey(Pos1(0)))
 Else Url:=BrowseUrl(NeedProject);
 If OptHas('no-browser')Then WriteLn(Url) Else OpenWeb(Url);
End;

Procedure CmdServerInfo;
Var
 J:LongInt;
Begin
 CmdBegin('serverinfo','');
 CmdExample('  jira serverinfo');
 OptG;
 ParseArgs(ArgStart);
 ApplyGlobals;
 RequireConfig;
 J:=ApiJ('GET',V2('/serverInfo'),'');
 WriteLn(Lg('Server Info','Informations du serveur'));
 WriteLn('  Base URL:        ',JS(J,'baseUrl'));
 WriteLn('  Version:         ',JS(J,'version'));
 WriteLn('  Deployment type: ',JS(J,'deploymentType'));
 WriteLn('  Build number:    ',JS(J,'buildNumber'));
 WriteLn('  Server title:    ',JS(J,'serverTitle'));
 WriteLn('  Server time:     ',JS(J,'serverTime'));
End;

Procedure CmdInit;
Var
 Inst,Srv,Login,Auth,Proj,Typ,Brd,Tok:AnsiString;
 Opts_:TSList;
 J,C,B:LongInt;
 R:THttpReq;
 Fld:LongInt;
Begin
 CmdBegin('init','');
 CmdExample('  # Interactive setup'#10'  jira init'#10#10'  # Non-interactive setup'#10'  JIRA_API_TOKEN=xxx jira init --installation cloud --server https://example.atlassian.net --login me@example.com --project PROJ --board none --force');
 Opt('installation','','string','Jira installation type: cloud or local@@Type d''installation Jira : cloud ou local');
 Opt('server','','string','Jira server URL@@URL du serveur Jira');
 Opt('login','','string','Jira login (email for cloud, username for local)@@Identifiant Jira (courriel pour cloud, nom pour local)');
 Opt('auth-type','','string','Authentication type: basic, bearer or mtls@@Type d''authentification : basic, bearer ou mtls');
 Opt('project','','string','Jira project key@@Cl'+#130+' du projet Jira');
 Opt('board','','string','Jira board name ("none" for no board)@@Nom du tableau Jira ('+#174+' none '+#175+' : aucun)');
 Opt('force','','','Overwrite existing config if it exists@@'+#144+'crase la configuration existante');
 OptG;
 ParseArgs(ArgStart);
 ApplyGlobals;
 If CfgExists and not OptHas('force')Then Begin
  If InteractiveOk Then Begin
   If not Confirm(Lg('Config already exists. Do you want to overwrite it?','La configuration existe d'+#130+'j'+#133+'. Voulez-vous l'''+#130+'craser ?'),False)Then Halt(0);
  End
  Else Die(Lg('Error: config already exists at ','Erreur : la configuration existe d'+#130+'j'+#133+' : ')+ConfigFile+Lg(' (use --force)',' (utilisez --force)'));
 End;
 NoInput:=False;
 Inst:=LoStr(OptGet('installation'));
 If Inst='' Then Begin
  If InteractiveOk Then Begin
   SClear(Opts_);SAdd(Opts_,'Cloud');SAdd(Opts_,'Local');
   Inst:=LoStr(Opts_.A[AskSelect(Lg('Installation type','Type d''installation'),Opts_)]);
  End
  Else Inst:='cloud';
 End;
 If(Inst<>'cloud')and(Inst<>'local')Then Die(Lg('Error: installation must be cloud or local','Erreur : installation doit valoir cloud ou local'));
 Srv:=OptGet('server');
 If Srv='' Then Begin
  If InteractiveOk Then Srv:=AskLine(Lg('Link to Jira server','Adresse du serveur Jira'),'')
  Else Die(Lg('Error: --server is required','Erreur : --server est obligatoire'));
 End;
 If(Pos('://',Srv)=0)Then Srv:='https://'+Srv;
 Srv:=StripSlash(Srv);
 Login:=OptGet('login');
 If Login='' Then Begin
  If InteractiveOk Then Login:=AskLine(Lg('Login email or username','Courriel ou nom d''utilisateur'),'')
  Else Die(Lg('Error: --login is required','Erreur : --login est obligatoire'));
 End;
 Auth:=LoStr(OptGet('auth-type'));
 If Auth='' Then Auth:='basic';
 If(Auth<>'basic')and(Auth<>'bearer')and(Auth<>'mtls')Then Die(Lg('Error: auth-type must be basic, bearer or mtls','Erreur : auth-type doit valoir basic, bearer ou mtls'));
 If OptHas('force')Then Begin SClear(CfgY.K);SClear(CfgY.V);End;
 JServer:=Srv;JLogin:=Login;JAuth:=Auth;
 If Inst='local' Then JInstall:='Local' Else JInstall:='Cloud';
 Tok:=ApiToken;
 If Tok='' Then Begin
  If InteractiveOk Then Begin
   Tok:=ReadSecret(Lg('? API token (not saved, export JIRA_API_TOKEN to reuse it): ','? Jeton d''API (non enregistr'+#130+', exportez JIRA_API_TOKEN pour le r'+#130+'utiliser) : '));
   If Tok<>'' Then TokenCache:=Tok;
  End;
 End;
 If ApiToken='' Then Die(Lg('Error: set the JIRA_API_TOKEN environment variable first','Erreur : d'+#130+'finissez d''abord la variable d''environnement JIRA_API_TOKEN'));
 J:=ApiJ('GET',V2('/myself'),'');
 If J<0 Then Die(Lg('Error: unable to verify credentials','Erreur : v'+#130+'rification des identifiants impossible'));
 { projet }
 Proj:=OptGet('project');
 If Proj='' Then Begin
  J:=ApiJ('GET',V2('/project'),'');
  SClear(Opts_);
  If(J>=0)and(JP[J].Kind=JK_ARR)Then Begin
   C:=JP[J].First;
   While C>=0 do Begin SAdd(Opts_,JS(C,'key')+'  '+JS(C,'name'));C:=JP[C].Next;End;
  End;
  If Opts_.N=0 Then Die(Lg('Error: no project found','Erreur : aucun projet trouv'+#130+''));
  If InteractiveOk Then Begin
   Proj:=Opts_.A[AskSelect(Lg('Default project','Projet par d'+#130+'faut'),Opts_)];
   Proj:=Copy(Proj,1,Pos(' ',Proj)-1);
  End
  Else Die(Lg('Error: --project is required','Erreur : --project est obligatoire'));
 End;
 Proj:=UpStr(Proj);
 J:=ApiJ('GET',V2('/project/'+UrlEnc(Proj,False)),'');
 Typ:='classic';
 If(JS(J,'style')='next-gen')or(JS(J,'simplified')='true')Then Typ:='next-gen';
 { tableau }
 Brd:='';
 B:=BoardsOf(Proj,'');
 If OptGet('board')<>'none' Then Begin
  SClear(Opts_);
  If JCnt(B)>0 Then Begin
   C:=JP[B].First;
   While C>=0 do Begin SAdd(Opts_,JS(C,'name'));C:=JP[C].Next;End;
  End;
  If OptHas('board')Then Brd:=OptGet('board')
  Else If(Opts_.N>0)and InteractiveOk Then Brd:=Opts_.A[AskSelect(Lg('Default board','Tableau par d'+#130+'faut'),Opts_)]
  Else If Opts_.N>0 Then Brd:=Opts_.A[0];
 End;
 YSet(CfgY,'installation',IfThen_(Inst='local','Local','Cloud'));
 YSet(CfgY,'server',Srv);
 YSet(CfgY,'login',Login);
 YSet(CfgY,'auth_type',Auth);
 YSet(CfgY,'project|key',Proj);
 YSet(CfgY,'project|type',Typ);
 If Brd<>'' Then Begin
  C:=JP[B].First;
  While C>=0 do Begin
   If JS(C,'name')=Brd Then Begin YSet(CfgY,'board|id',JS(C,'id'));YSet(CfgY,'board|name',Brd);Break;End;
   C:=JP[C].Next;
  End;
 End;
 FieldsNode:=-2;
 Fld:=AllFields;
 C:=JP[Fld].First;
 While C>=0 do Begin
  If LoStr(JS(C,'name'))='epic name' Then YSet(CfgY,'epic|name',JS(C,'id'));
  If LoStr(JS(C,'name'))='epic link' Then YSet(CfgY,'epic|link',JS(C,'id'));
  C:=JP[C].Next;
 End;
 SaveJiraConfig;
 WriteLn(OkMark,' ',Lg('Configuration generated: ','Configuration g'+#130+'n'+#130+'r'+#130+'e : '),ConfigFile);
End;

Procedure CmdVersion;
Begin
 CmdBegin('version','');
 OptG;
 ParseArgs(ArgStart);
 WriteLn('Version:    ',ToolVersion);
 WriteLn('Go version: Free Pascal');
 WriteLn('Platform:   ',IfThen_(DS='\','windows','unix'));
End;
{ ------------------------------------------------------------------ }
{ Aide, completion, manuel, table des commandes et programme          }
{ ------------------------------------------------------------------ }

Type
 TProc = Procedure;
 TDisp = Record
  P:AnsiString;
  F:TProc;
 End;

Procedure CmdCompletion;
Forward;
Procedure CmdMan;
Forward;

Const
 NDsp=36;
 Disp:Array[0..NDsp-1]of TDisp=(
  (P:'board list';F:@CmdBoardList),
  (P:'completion';F:@CmdCompletion),
  (P:'epic add';F:@CmdEpicAdd),
  (P:'epic create';F:@CmdEpicCreate),
  (P:'epic list';F:@CmdEpicList),
  (P:'epic remove';F:@CmdEpicRemove),
  (P:'init';F:@CmdInit),
  (P:'issue assign';F:@CmdIssueAssign),
  (P:'issue clone';F:@CmdIssueClone),
  (P:'issue comment add';F:@CmdIssueCommentAdd),
  (P:'issue create';F:@CmdIssueCreate),
  (P:'issue delete';F:@CmdIssueDelete),
  (P:'issue edit';F:@CmdIssueEdit),
  (P:'issue link';F:@CmdIssueLink),
  (P:'issue link remote';F:@CmdIssueLinkRemote),
  (P:'issue list';F:@CmdIssueList),
  (P:'issue move';F:@CmdIssueMove),
  (P:'issue unlink';F:@CmdIssueUnlink),
  (P:'issue view';F:@CmdIssueView),
  (P:'issue worklog add';F:@CmdWorklogAdd),
  (P:'man';F:@CmdMan),
  (P:'me';F:@CmdMe),
  (P:'open';F:@CmdOpen),
  (P:'project list';F:@CmdProjectList),
  (P:'release list';F:@CmdReleaseList),
  (P:'serverinfo';F:@CmdServerInfo),
  (P:'sprint add';F:@CmdSprintAdd),
  (P:'sprint close';F:@CmdSprintClose),
  (P:'sprint list';F:@CmdSprintList),
  (P:'version';F:@CmdVersion),
  (P:'';F:Nil),(P:'';F:Nil),(P:'';F:Nil),(P:'';F:Nil),(P:'';F:Nil),(P:'';F:Nil));

Function FindDisp(Const Path:AnsiString):TProc;
Var
 I:LongInt;
Begin
 FindDisp:=Nil;
 For I:=0 to NDsp-1 do If(Disp[I].P<>'')and(Disp[I].P=Path)Then Begin FindDisp:=Disp[I].F;Exit;End;
End;

{ sous-commandes (mot suivant) d'un groupe ; Group='' : commandes de premier niveau }
Procedure ChildrenOf(Const Group:AnsiString;Var L:TSList);
Var
 I,P:LongInt;
 R,W:AnsiString;
Begin
 SClear(L);
 For I:=0 to NDsp-1 do Begin
  If Disp[I].P='' Then Continue;
  If Group='' Then R:=Disp[I].P
  Else If StartsWith(Disp[I].P,Group+' ')Then R:=Copy(Disp[I].P,Length(Group)+2,Length(Disp[I].P))
  Else Continue;
  P:=Pos(' ',R);
  If P>0 Then W:=Copy(R,1,P-1) Else W:=R;
  If SIndex(L,W)<0 Then SAdd(L,W);
 End;
 SSort(L);
End;

Function IsGroup(Const Path:AnsiString):Boolean;
Var
 L:TSList;
Begin
 ChildrenOf(Path,L);
 IsGroup:=(L.N>0)and(FindDisp(Path)=Nil);
End;

Procedure PrintGroupHelp(Const Group:AnsiString);
Var
 L:TSList;
 I,W:LongInt;
 Pre,D:AnsiString;
Begin
 ChildrenOf(Group,L);
 If Group='' Then Pre:='' Else Pre:=Group+' ';
 D:=DescOf(Group);
 If D<>'' Then WriteLn(D);
 WriteLn;
 WriteLn(Lg('Usage:','Utilisation :'));
 WriteLn('  jira ',Pre,Lg('[command]','[commande]'));
 WriteLn;
 WriteLn(Lg('Available Commands:','Commandes disponibles :'));
 W:=0;
 For I:=0 to L.N-1 do If Length(L.A[I])>W Then W:=Length(L.A[I]);
 For I:=0 to L.N-1 do WriteLn('  ',PadR(L.A[I],W),'   ',DescOf(Pre+L.A[I]));
 If Group='' Then Begin
  WriteLn;
  WriteLn(Lg('Flags:','Options :'));
  WriteLn('  -c, --config string    ',Lg('Config file (default is $HOME/.config/.jira/.config.yml)','Fichier de configuration (d'+#130+'faut : $HOME/.config/.jira/.config.yml)'));
  WriteLn('      --debug            ',Lg('Turn on debug output','Active la sortie de d'+#130+'bogage'));
  WriteLn('  -h, --help             ',Lg('help for jira','aide de jira'));
  WriteLn('  -p, --project string   ',Lg('Jira project to look into (defaults to project in the config file)','Projet Jira '+#133+' utiliser (d'+#130+'faut : projet du fichier de configuration)'));
  WriteLn('  -v, --version          ',Lg('version for jira','version de jira'));
 End
 Else Begin
  WriteLn;
  WriteLn(Lg('Flags:','Options :'));
  WriteLn('  -h, --help   ',Lg('help for ','aide de '),Copy(Group,LastDelimPos(Group)+1,Length(Group)));
 End;
 WriteLn;
 WriteLn(Lg('Use "jira ','Utilisez "jira '),Pre,Lg('[command] --help" for more information about a command.','[commande] --help" pour plus d''informations.'));
End;

{ ------------------------------------------------------------------ }
{ Completion du shell                                                 }
{ ------------------------------------------------------------------ }

Procedure CmdCompletion;
Var
 Sh:AnsiString;
 Top,Sub:TSList;
 I:LongInt;
 Words:AnsiString;
Begin
 CmdBegin('completion','bash|zsh|fish|powershell');
 CmdExample('  # bash'#10'  source <(jira completion bash)'#10#10'  # zsh'#10'  jira completion zsh > "${fpath[1]}/_jira"'#10#10'  # fish'#10'  jira completion fish | source');
 OptG;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 Sh:=LoStr(Pos1(0));
 ChildrenOf('',Top);
 If Sh='bash' Then Begin
  WriteLn('_jira_completions() {');
  WriteLn('  local cur="${COMP_WORDS[COMP_CWORD]}"');
  WriteLn('  if [ "$COMP_CWORD" -le 1 ]; then');
  WriteLn('    COMPREPLY=($(compgen -W "',JoinList(Top,' '),' help" -- "$cur"))');
  WriteLn('    return');
  WriteLn('  fi');
  WriteLn('  case "${COMP_WORDS[1]}" in');
  For I:=0 to Top.N-1 do Begin
   ChildrenOf(Top.A[I],Sub);
   If Sub.N>0 Then WriteLn('    ',Top.A[I],') COMPREPLY=($(compgen -W "',JoinList(Sub,' '),'" -- "$cur")) ;;');
  End;
  WriteLn('  esac');
  WriteLn('}');
  WriteLn('complete -F _jira_completions jira');
 End
 Else If Sh='zsh' Then Begin
  WriteLn('#compdef jira');
  WriteLn('_jira() {');
  WriteLn('  local -a cmds');
  WriteLn('  if (( CURRENT == 2 )); then');
  WriteLn('    cmds=(',JoinList(Top,' '),' help)');
  WriteLn('    _describe ''command'' cmds');
  WriteLn('    return');
  WriteLn('  fi');
  WriteLn('  case $words[2] in');
  For I:=0 to Top.N-1 do Begin
   ChildrenOf(Top.A[I],Sub);
   If Sub.N>0 Then WriteLn('    ',Top.A[I],') cmds=(',JoinList(Sub,' '),'); _describe ''command'' cmds ;;');
  End;
  WriteLn('  esac');
  WriteLn('}');
  WriteLn('compdef _jira jira');
 End
 Else If Sh='fish' Then Begin
  WriteLn('complete -c jira -f');
  WriteLn('complete -c jira -n ''__fish_use_subcommand'' -a ''',JoinList(Top,' '),' help''');
  For I:=0 to Top.N-1 do Begin
   ChildrenOf(Top.A[I],Sub);
   If Sub.N>0 Then WriteLn('complete -c jira -n ''__fish_seen_subcommand_from ',Top.A[I],''' -a ''',JoinList(Sub,' '),'''');
  End;
 End
 Else If(Sh='powershell')or(Sh='pwsh')Then Begin
  WriteLn('Register-ArgumentCompleter -Native -CommandName jira -ScriptBlock {');
  WriteLn('  param($wordToComplete, $commandAst, $cursorPosition)');
  WriteLn('  $words = $commandAst.CommandElements | ForEach-Object { $_.ToString() }');
  WriteLn('  $top = @(',ReplaceAll('''' + JoinList(Top,''','''),'''',''''),''')');
  Words:='';
  WriteLn('  $sub = @{');
  For I:=0 to Top.N-1 do Begin
   ChildrenOf(Top.A[I],Sub);
   If Sub.N>0 Then WriteLn('    ''',Top.A[I],''' = @(''',JoinList(Sub,''','''),''')');
  End;
  WriteLn('  }');
  WriteLn('  $list = if ($words.Count -le 2) { $top } else { $sub[$words[1]] }');
  WriteLn('  $list | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {');
  WriteLn('    [System.Management.Automation.CompletionResult]::new($_, $_, ''ParameterValue'', $_)');
  WriteLn('  }');
  WriteLn('}');
 End
 Else Die(Lg('Error: unsupported shell "','Erreur : shell non pris en charge "')+Sh+'" (bash, zsh, fish, powershell)');
End;

Procedure CmdMan;
Var
 Top,Sub:TSList;
 I,J:LongInt;
 P:AnsiString;
Begin
 CmdBegin('man','');
 OptG;
 ParseArgs(ArgStart);
 WriteLn('.TH "JIRA" "1" "" "jira ',ToolVersion,'" ""');
 WriteLn('.SH NAME');
 WriteLn('jira \- ',DescOf(''));
 WriteLn('.SH SYNOPSIS');
 WriteLn('\fBjira\fP <command> <subcommand> [flags]');
 WriteLn('.SH COMMANDS');
 ChildrenOf('',Top);
 For I:=0 to Top.N-1 do Begin
  ChildrenOf(Top.A[I],Sub);
  If Sub.N=0 Then Begin
   WriteLn('.TP');WriteLn('\fBjira ',Top.A[I],'\fP');WriteLn(DescOf(Top.A[I]));
  End
  Else For J:=0 to Sub.N-1 do Begin
   P:=Top.A[I]+' '+Sub.A[J];
   WriteLn('.TP');WriteLn('\fBjira ',P,'\fP');WriteLn(DescOf(P));
  End;
 End;
 WriteLn('.SH OPTIONS');
 WriteLn('.TP');WriteLn('\fB\-c\fP, \fB\-\-config\fP');WriteLn('Config file');
 WriteLn('.TP');WriteLn('\fB\-p\fP, \fB\-\-project\fP');WriteLn('Jira project');
 WriteLn('.TP');WriteLn('\fB\-\-debug\fP');WriteLn('Turn on debug output');
End;

{ ------------------------------------------------------------------ }
{ Programme principal                                                 }
{ ------------------------------------------------------------------ }

Procedure NoSuchCommand(Const Parent,Sub:AnsiString);
Begin
 WriteLn(StdErr,'Error: unknown command "',Sub,'" for "',IfThen_(Parent='','jira','jira '+Parent),'"');
 WriteLn(StdErr,Lg('Run ''jira ','Ex'+#130+'cutez ''jira '),IfThen_(Parent='','',Parent+' '),Lg('--help'' for usage.','--help'' pour l''aide.'));
 Halt(1);
End;

{ synonymes d'un dernier mot de commande }
Function Synonym(Const W:AnsiString;N:LongInt):AnsiString;
Begin
 Synonym:='';
 If(W='ls')or(W='lists')Then Begin If N=0 Then Synonym:='list';End
 Else If W='new' Then Begin If N=0 Then Synonym:='create';End
 Else If W='show' Then Begin If N=0 Then Synonym:='view';End
 Else If W='modify' Then Begin If N=0 Then Synonym:='edit';End
 Else If(W='mv')or(W='transition')Then Begin If N=0 Then Synonym:='move';End
 Else If W='asg' Then Begin If N=0 Then Synonym:='assign';End
 Else If W='browse' Then Begin If N=0 Then Synonym:='open';End
 Else If(W='rm')or(W='remove')or(W='del')Then Begin
  If N=0 Then Synonym:='delete' Else If N=1 Then Synonym:='remove';
 End;
End;

{ commande correspondant aux N premiers mots (synonymes du dernier mot acceptes) }
Function Resolve(Var Words:Array of AnsiString;N:LongInt;Var Path:AnsiString):TProc;
Var
 K,J:LongInt;
 Pre,Alt:AnsiString;
Begin
 Pre:='';
 For K:=0 to N-2 do Pre:=Pre+Words[K]+' ';
 Path:=Pre+Words[N-1];
 Resolve:=FindDisp(Path);
 If Resolve<>Nil Then Exit;
 For J:=0 to 1 do Begin
  Alt:=Synonym(Words[N-1],J);
  If Alt<>'' Then Begin
   Path:=Pre+Alt;
   Resolve:=FindDisp(Path);
   If Resolve<>Nil Then Exit;
  End;
 End;
End;

Procedure Run;
Var
 Words:Array[0..3]of AnsiString;
 NW,N,I:LongInt;
 Path,Grp:AnsiString;
 P:TProc;
 A1:AnsiString;
Begin
 If ParamCount=0 Then Begin PrintGroupHelp('');Halt(0);End;
 A1:=ParamStr(1);
 If(A1='--help')or(A1='-h')Then Begin PrintGroupHelp('');Halt(0);End;
 If(A1='--version')or(A1='-v')Then Begin WriteLn('jira version ',ToolVersion);Halt(0);End;
 If A1='help' Then Begin
  Path:='';
  For I:=2 to ParamCount do Path:=Path+IfThen_(Path<>'',' ','')+ParamStr(I);
  If Path='' Then PrintGroupHelp('')
  Else If IsGroup(Path)Then PrintGroupHelp(Path)
  Else If FindDisp(Path)<>Nil Then Halt(RunShell(Q(ParamStr(0))+' '+Path+' --help'))
  Else NoSuchCommand('',ParamStr(2));
  Halt(0);
 End;
 NW:=0;
 While(NW<ParamCount)and(NW<4)and(Copy(ParamStr(NW+1),1,1)<>'-')do Begin
  Words[NW]:=ParamStr(NW+1);Inc(NW);
 End;
 If NW=0 Then Begin
  WriteLn(StdErr,'Error: unknown flag: ',ParamStr(1));
  Halt(1);
 End;
 For N:=NW downto 1 do Begin
  P:=Resolve(Words,N,Path);
  If P<>Nil Then Begin
   ArgStart:=N+1;
   P();
   Halt(0);
  End;
 End;
 { groupe sans sous-commande : aide du groupe }
 For N:=NW downto 1 do Begin
  Grp:='';
  For I:=0 to N-1 do Grp:=Grp+IfThen_(I>0,' ','')+Words[I];
  If IsGroup(Grp)Then Begin
   If N<NW Then NoSuchCommand(Grp,Words[N]);
   PrintGroupHelp(Grp);
   Halt(0);
  End;
 End;
 If NW>=2 Then NoSuchCommand('',Words[0]);
 NoSuchCommand('',Words[0]);
End;

{$IFDEF WINDOWS}
Function SetConsoleOutputCP(CP:LongWord):LongInt;stdcall;external 'kernel32.dll' name
  'SetConsoleOutputCP';
Function GetConsoleOutputCP:LongWord;stdcall;external 'kernel32.dll' name
  'GetConsoleOutputCP';

Var
 SavedCP:LongWord;
 OldExit:Pointer;

Procedure RestoreConsole;
Begin
 ExitProc:=OldExit;
 SetConsoleOutputCP(SavedCP);
End;
{$ENDIF}

Begin
 Randomize;
 JN:=0;
 {$IFDEF WINDOWS}
 SavedCP:=GetConsoleOutputCP;
 SetConsoleOutputCP(65001);
 OldExit:=ExitProc;
 ExitProc:=@RestoreConsole;
 {$ENDIF}
 InstallUtf8Output;
 DetectTTY;
 Run;
End.

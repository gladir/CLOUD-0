{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/cloud-0)
  @website(https://www.gladir.com/vie)
  @abstract(Target: Free Pascal 3.x)

  GH : clone de la commande gh (GitHub CLI).

  (documentation completee a la fin du developpement)
}

Program GH;

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
 ToolVersion  = '1.0.0';
 UserAgent    = 'GitHub CLI pascal/1.0.0';
 ClientId     = '178c6fc778ccc68e1d6a';
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
 Result:='Accept-Encoding: identity'#13#10'X-GitHub-Api-Version: 2022-11-28'#13#10;
 If Pos('accept:',LoStr(R.Headers))=0 Then Result:=Result+'Accept: application/vnd.github+json'#13#10;
 {$IFNDEF WINDOWS}
 Result:=Result+'User-Agent: '+UserAgent+#13#10;
 {$ENDIF}
 If R.Token<>'' Then Result:=Result+'Authorization: Bearer '+R.Token+#13#10;
 If R.ResumeFrom>0 Then Result:=Result+'Range: bytes='+IStr(R.ResumeFrom)+'-'#13#10;
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
 TempName:=DropSlash(D)+'/ghpas'+IStr(Random(1000000000))+Tag;
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
 NDesc=199;
 Descs:Array[0..NDesc-1]of TCmdDesc=(
  (P:'alias';D:'Create command shortcuts@@Cr'#130'e des raccourcis de commandes'),
  (P:'alias delete';D:'Delete set aliases@@Supprime des alias d'#130'finis'),
  (P:'alias imports';D:'Import aliases from a YAML file@@Importe des alias depuis un fichier YAML'),
  (P:'alias list';D:'List your aliases@@Liste vos alias'),
  (P:'alias set';D:'Create a shortcut for a gh command@@Cr'#130'e un raccourci pour une commande gh'),
  (P:'api';D:'Make an authenticated GitHub API request@@Effectue une requ'#136'te authentifi'#130+
   'e '#133' l''API GitHub'),
  (P:'auth';D:'Authenticate gh and git with GitHub@@Authentifie gh et git aupr'#138's de GitHub'),
  (P:'auth login';D:'Log in to a GitHub account@@Ouvre une session sur un compte GitHub'),
  (P:'auth logout';D:'Log out of a GitHub account@@Ferme la session d''un compte GitHub'),
  (P:'auth refresh';D:'Refresh stored authentication credentials@@Renouvelle les identifiants stock'+
   #130's'),
  (P:'auth setup-git';D:'Setup git with GitHub CLI@@Configure git pour utiliser GitHub CLI'),
  (P:'auth status';D:'Display active account and authentication state on each known GitHub host@@Af'+
   'fiche le compte actif et l'''#130'tat de l''authentification pour chaque h'#147'te GitHub'),
  (P:'auth switch';D:'Switch active GitHub account@@Change de compte GitHub actif'),
  (P:'auth token';D:'Print the authentication token gh uses for a hostname and account@@Affiche le '+
   'jeton d''authentification utilis'#130' par gh pour un h'#147'te et un compte'),
  (P:'browse';D:'Open repositories, issues, pull requests, and more in the browser@@Ouvre des d'#130+
   'p'#147'ts, tickets, pull requests et plus dans le navigateur'),
  (P:'cache';D:'Manage GitHub Actions caches@@G'#138're les caches de GitHub Actions'),
  (P:'cache delete';D:'Delete GitHub Actions caches@@Supprime des caches de GitHub Actions'),
  (P:'cache list';D:'List GitHub Actions caches@@Liste les caches de GitHub Actions'),
  (P:'codespace';D:'Connect to and manage codespaces@@Se connecte aux codespaces et les g'#138're'),
  (P:'codespace create';D:'Create a codespace@@Cr'#130'e un codespace'),
  (P:'codespace delete';D:'Delete codespaces@@Supprime des codespaces'),
  (P:'codespace edit';D:'Edit a codespace@@Modifie un codespace'),
  (P:'codespace list';D:'List codespaces@@Liste les codespaces'),
  (P:'codespace rebuild';D:'Rebuild a codespace@@Reconstruit un codespace'),
  (P:'codespace stop';D:'Stop a running codespace@@Arr'#136'te un codespace en cours d''ex'#130'cution'),
  (P:'codespace view';D:'View details about a codespace@@Affiche les d'#130'tails d''un codespace'),
  (P:'codespace ssh';D:'SSH into a codespace (not supported by this clone)@@Connexion SSH '#133' un code'+
   'space (non prise en charge par ce clone)'),
  (P:'codespace code';D:'Open a codespace in Visual Studio Code@@Ouvre un codespace dans Visual Stud'+
   'io Code'),
  (P:'codespace cp';D:'Copy files between local and remote file systems (not supported)@@Copie des f'+
   'ichiers entre les syst'#138'mes local et distant (non pris en charge)'),
  (P:'codespace logs';D:'Access codespace logs (not supported)@@Acc'#138'de aux journaux d''un codespace '+
   '(non pris en charge)'),
  (P:'codespace ports';D:'List ports in a codespace@@Liste les ports d''un codespace'),
  (P:'codespace jupyter';D:'Open a codespace in JupyterLab (not supported)@@Ouvre un codespace dans Ju'+
   'pyterLab (non pris en charge)'),
  (P:'completion';D:'Generate shell completion scripts@@G'#130'n'#138're des scripts d''autocompl'#130'tion'),
  (P:'config';D:'Manage configuration for gh@@G'#138're la configuration de gh'),
  (P:'config clear-cache';D:'Clear the cli cache@@Vide le cache de la CLI'),
  (P:'config get';D:'Print the value of a given configuration key@@Affiche la valeur d''une cl'#130+
   ' de configuration'),
  (P:'config list';D:'Print a list of configuration keys and values@@Affiche les cl'#130's de configu'+
   'ration et leurs valeurs'),
  (P:'config set';D:'Update configuration with a value for the given key@@Modifie la valeur d''une c'+
   'l'#130' de configuration'),
  (P:'extension';D:'Manage gh extensions@@G'#138're les extensions de gh'),
  (P:'extension browse';D:'Enter a UI for browsing gh extensions@@Parcourt les extensions gh'),
  (P:'extension create';D:'Create a new extension@@Cr'#130'e une nouvelle extension'),
  (P:'extension exec';D:'Execute an installed extension@@Ex'#130'cute une extension install'#130'e'),
  (P:'extension install';D:'Install a gh extension from a repository@@Installe une extension gh depuis '+
   'un d'#130'p'#147't'),
  (P:'extension list';D:'List installed extension commands@@Liste les extensions install'#130'es'),
  (P:'extension remove';D:'Remove an installed extension@@Supprime une extension install'#130'e'),
  (P:'extension search';D:'Search extensions to the GitHub CLI@@Recherche des extensions pour GitHub CLI'),
  (P:'extension upgrade';D:'Upgrade installed extensions@@Met '#133' jour les extensions install'#130'es'),
  (P:'gist';D:'Manage gists@@G'#138're les gists'),
  (P:'gist clone';D:'Clone a gist locally@@Clone un gist localement'),
  (P:'gist create';D:'Create a new gist@@Cr'#130'e un nouveau gist'),
  (P:'gist delete';D:'Delete a gist@@Supprime un gist'),
  (P:'gist edit';D:'Edit one of your gists@@Modifie un de vos gists'),
  (P:'gist list';D:'List your gists@@Liste vos gists'),
  (P:'gist rename';D:'Rename a file in a gist@@Renomme un fichier dans un gist'),
  (P:'gist view';D:'View a gist@@Affiche un gist'),
  (P:'gpg-key';D:'Manage GPG keys@@G'#138're les cl'#130's GPG'),
  (P:'gpg-key add';D:'Add a GPG key to your GitHub account@@Ajoute une cl'#130' GPG '#133' votre compte GitHub'),
  (P:'gpg-key delete';D:'Delete a GPG key from your GitHub account@@Supprime une cl'#130' GPG de votre co'+
   'mpte GitHub'),
  (P:'gpg-key list';D:'Lists GPG keys in your GitHub account@@Liste les cl'#130's GPG de votre compte GitHub'),
  (P:'help';D:'Help about any command@@Aide sur n''importe quelle commande'),
  (P:'issue';D:'Manage issues@@G'#138're les tickets'),
  (P:'issue close';D:'Close issue@@Ferme un ticket'),
  (P:'issue comment';D:'Add a comment to an issue@@Ajoute un commentaire '#133' un ticket'),
  (P:'issue create';D:'Create a new issue@@Cr'#130'e un nouveau ticket'),
  (P:'issue delete';D:'Delete issue@@Supprime un ticket'),
  (P:'issue develop';D:'Manage linked branches for an issue@@G'#138're les branches li'#130'es '#133' un ticket'),
  (P:'issue edit';D:'Edit issues@@Modifie des tickets'),
  (P:'issue list';D:'List issues in a repository@@Liste les tickets d''un d'#130'p'#147't'),
  (P:'issue lock';D:'Lock issue conversation@@Verrouille la conversation d''un ticket'),
  (P:'issue pin';D:'Pin a issue to a repository@@'#144'pingle un ticket dans un d'#130'p'#147't'),
  (P:'issue reopen';D:'Reopen issue@@Rouvre un ticket'),
  (P:'issue status';D:'Show status of relevant issues@@Affiche l'''#130'tat des tickets pertinents'),
  (P:'issue transfer';D:'Transfer issue to another repository@@Transf'#138're un ticket vers un autre d'#130'p'+
   #147't'),
  (P:'issue unlock';D:'Unlock issue conversation@@D'#130'verrouille la conversation d''un ticket'),
  (P:'issue unpin';D:'Unpin a issue from a repository@@D'#130'tache un ticket d''un d'#130'p'#147't'),
  (P:'issue view';D:'View an issue@@Affiche un ticket'),
  (P:'label';D:'Manage labels@@G'#138're les '#130'tiquettes'),
  (P:'label clone';D:'Clones labels from one repository to another@@Copie les '#130'tiquettes d''un d'#130'p'+
   #147't vers un autre'),
  (P:'label create';D:'Create a new label@@Cr'#130'e une nouvelle '#130'tiquette'),
  (P:'label delete';D:'Delete a label from a repository@@Supprime une '#130'tiquette d''un d'#130'p'#147't'),
  (P:'label edit';D:'Edit a label@@Modifie une '#130'tiquette'),
  (P:'label list';D:'List labels in a repository@@Liste les '#130'tiquettes d''un d'#130'p'#147't'),
  (P:'org';D:'Manage organizations@@G'#138're les organisations'),
  (P:'org list';D:'List organizations for the authenticated user.@@Liste les organisations de l''util'+
   'isateur authentifi'#130'.'),
  (P:'pr';D:'Manage pull requests@@G'#138're les pull requests'),
  (P:'pr checkout';D:'Check out a pull request in git@@R'#130'cup'#138're une pull request dans git'),
  (P:'pr checks';D:'Show CI status for a single pull request@@Affiche l'''#130'tat de l''IC d''une pull re'+
   'quest'),
  (P:'pr close';D:'Close a pull request@@Ferme une pull request'),
  (P:'pr comment';D:'Add a comment to a pull request@@Ajoute un commentaire '#133' une pull request'),
  (P:'pr create';D:'Create a pull request@@Cr'#130'e une pull request'),
  (P:'pr diff';D:'View changes in a pull request@@Affiche les modifications d''une pull request'),
  (P:'pr edit';D:'Edit a pull request@@Modifie une pull request'),
  (P:'pr list';D:'List pull requests in a repository@@Liste les pull requests d''un d'#130'p'#147't'),
  (P:'pr lock';D:'Lock pull request conversation@@Verrouille la conversation d''une pull request'),
  (P:'pr merge';D:'Merge a pull request@@Fusionne une pull request'),
  (P:'pr ready';D:'Mark a pull request as ready for review@@Marque une pull request comme pr'#136'te '+
   'pour r'#130'vision'),
  (P:'pr reopen';D:'Reopen a pull request@@Rouvre une pull request'),
  (P:'pr revert';D:'Revert a pull request@@Annule une pull request'),
  (P:'pr review';D:'Add a review to a pull request@@Ajoute une r'#130'vision '#133' une pull request'),
  (P:'pr status';D:'Show status of relevant pull requests@@Affiche l'''#130'tat des pull requests perti'+
   'nentes'),
  (P:'pr unlock';D:'Unlock pull request conversation@@D'#130'verrouille la conversation d''une pull req'+
   'uest'),
  (P:'pr update-branch';D:'Update a pull request branch@@Met '#133' jour la branche d''une pull request'),
  (P:'pr view';D:'View a pull request@@Affiche une pull request'),
  (P:'project';D:'Work with GitHub Projects.@@Travaille avec les projets GitHub.'),
  (P:'project close';D:'Close a project@@Ferme un projet'),
  (P:'project copy';D:'Copy a project@@Copie un projet'),
  (P:'project create';D:'Create a project@@Cr'#130'e un projet'),
  (P:'project delete';D:'Delete a project@@Supprime un projet'),
  (P:'project edit';D:'Edit a project@@Modifie un projet'),
  (P:'project field-create';D:'Create a field in a project@@Cr'#130'e un champ dans un projet'),
  (P:'project field-delete';D:'Delete a field in a project@@Supprime un champ d''un projet'),
  (P:'project field-list';D:'List the fields in a project@@Liste les champs d''un projet'),
  (P:'project item-add';D:'Add a pull request or an issue to a project@@Ajoute une pull request ou u'+
   'n ticket '#133' un projet'),
  (P:'project item-archive';D:'Archive an item in a project@@Archive un '#130'l'#130'ment d''un projet'),
  (P:'project item-create';D:'Create a draft issue item in a project@@Cr'#130'e un brouillon de ticket'+
   ' dans un projet'),
  (P:'project item-delete';D:'Delete an item from a project by ID@@Supprime un '#130'l'#130'ment d''un pro'+
   'jet'),
  (P:'project item-edit';D:'Edit an item in a project@@Modifie un '#130'l'#130'ment d''un projet'),
  (P:'project item-list';D:'List the items in a project@@Liste les '#130'l'#130'ments d''un projet'),
  (P:'project link';D:'Link a project to a repository or a team@@Lie un projet '#133' un d'#130'p'#147't ou '+
   #133' une '#130'quipe'),
  (P:'project list';D:'List the projects for an owner@@Liste les projets d''un propri'#130'taire'),
  (P:'project mark-template';D:'Mark a project as a template@@Marque un projet comme mod'#138'le'),
  (P:'project unlink';D:'Unlink a project from a repository or a team@@D'#130'lie un projet d''un d'#130+
   'p'#147't ou d''une '#130'quipe'),
  (P:'project view';D:'View a project@@Affiche un projet'),
  (P:'release';D:'Manage releases@@G'#138're les versions publi'#130'es'),
  (P:'release create';D:'Create a new release@@Cr'#130'e une nouvelle version'),
  (P:'release delete';D:'Delete a release@@Supprime une version'),
  (P:'release delete-asset';D:'Delete an asset from a release@@Supprime un fichier d''une version'),
  (P:'release download';D:'Download release assets@@T'#130'l'#130'charge les fichiers d''une version'),
  (P:'release edit';D:'Edit a release@@Modifie une version'),
  (P:'release list';D:'List releases in a repository@@Liste les versions d''un d'#130'p'#147't'),
  (P:'release upload';D:'Upload assets to a GitHub Release@@Envoie des fichiers vers une version'),
  (P:'release view';D:'View information about a release@@Affiche les informations d''une version'),
  (P:'repo';D:'Manage repositories@@G'#138're les d'#130'p'#147'ts'),
  (P:'repo archive';D:'Archive a repository@@Archive un d'#130'p'#147't'),
  (P:'repo autolink';D:'Manage autolink references@@G'#138're les r'#130'f'#130'rences automatiques (autolinks)'),
  (P:'repo autolink create';D:'Create a new autolink reference@@Cr'#130'e une r'#130'f'#130'rence automatique'),
  (P:'repo autolink delete';D:'Delete an autolink reference@@Supprime une r'#130'f'#130'rence automatique'),
  (P:'repo autolink list';D:'List autolink references for a GitHub repository@@Liste les r'#130'f'#130'rences'+
   ' automatiques d''un d'#130'p'#147't'),
  (P:'repo autolink view';D:'View an autolink reference@@Affiche une r'#130'f'#130'rence automatique'),
  (P:'repo clone';D:'Clone a repository locally@@Clone un d'#130'p'#147't localement'),
  (P:'repo create';D:'Create a new repository@@Cr'#130'e un nouveau d'#130'p'#147't'),
  (P:'repo delete';D:'Delete a repository@@Supprime un d'#130'p'#147't'),
  (P:'repo deploy-key';D:'Manage deploy keys in a repository@@G'#138're les cl'#130's de d'#130'ploiement d''un '+
   'd'#130'p'#147't'),
  (P:'repo deploy-key add';D:'Add a deploy key to a GitHub repository@@Ajoute une cl'#130' de d'#130'ploiem'+
   'ent '#133' un d'#130'p'#147't'),
  (P:'repo deploy-key delete';D:'Delete a deploy key from a GitHub repository@@Supprime une cl'#130' de d'+
   #130'ploiement d''un d'#130'p'#147't'),
  (P:'repo deploy-key list';D:'List deploy keys in a GitHub repository@@Liste les cl'#130's de d'#130'ploie'+
   'ment d''un d'#130'p'#147't'),
  (P:'repo edit';D:'Edit repository settings@@Modifie les param'#138'tres d''un d'#130'p'#147't'),
  (P:'repo fork';D:'Create a fork of a repository@@Cr'#130'e une copie d'#130'riv'#130'e (fork) d''un d'#130'p'#147't'),
  (P:'repo gitignore';D:'List and view available repository gitignore templates@@Liste et affiche les'+
   ' mod'#138'les .gitignore disponibles'),
  (P:'repo gitignore list';D:'List available repository gitignore templates@@Liste les mod'#138'les .git'+
   'ignore disponibles'),
  (P:'repo gitignore view';D:'View an available repository .gitignore template@@Affiche un mod'#138'le .'+
   'gitignore'),
  (P:'repo license';D:'Explore repository licenses@@Explore les licences de d'#130'p'#147't'),
  (P:'repo license list';D:'List common repository licenses@@Liste les licences courantes'),
  (P:'repo license view';D:'View a specific repository license@@Affiche une licence de d'#130'p'#147't'),
  (P:'repo list';D:'List repositories owned by user or organization@@Liste les d'#130'p'#147'ts d''un utilis'+
   'ateur ou d''une organisation'),
  (P:'repo rename';D:'Rename a repository@@Renomme un d'#130'p'#147't'),
  (P:'repo set-default';D:'Configure default repository for this directory@@Configure le d'#130'p'#147't p'+
   'ar d'#130'faut de ce r'#130'pertoire'),
  (P:'repo sync';D:'Sync a repository@@Synchronise un d'#130'p'#147't'),
  (P:'repo unarchive';D:'Unarchive a repository@@D'#130'sarchive un d'#130'p'#147't'),
  (P:'repo view';D:'View a repository@@Affiche un d'#130'p'#147't'),
  (P:'ruleset';D:'View info about repo rulesets@@Affiche les ensembles de r'#138'gles d''un d'#130'p'#147't'),
  (P:'ruleset check';D:'View rules that would apply to a given branch@@Affiche les r'#138'gles qui s''ap'+
   'pliquent '#133' une branche'),
  (P:'ruleset list';D:'List rulesets for a repository or organization@@Liste les ensembles de r'#138'gl'+
   'es d''un d'#130'p'#147't ou d''une organisation'),
  (P:'ruleset view';D:'View information about a ruleset@@Affiche un ensemble de r'#138'gles'),
  (P:'run';D:'View details about workflow runs@@Affiche les d'#130'tails des ex'#130'cutions de workflows'),
  (P:'run cancel';D:'Cancel a workflow run@@Annule une ex'#130'cution de workflow'),
  (P:'run delete';D:'Delete a workflow run@@Supprime une ex'#130'cution de workflow'),
  (P:'run download';D:'Download artifacts generated by a workflow run@@T'#130'l'#130'charge les artefacts g'#130'n'+
   #130'r'#130's par une ex'#130'cution'),
  (P:'run list';D:'List recent workflow runs@@Liste les ex'#130'cutions r'#130'centes de workflows'),
  (P:'run rerun';D:'Rerun a run@@Relance une ex'#130'cution'),
  (P:'run view';D:'View a summary of a workflow run@@Affiche le r'#130'sum'#130' d''une ex'#130'cution'),
  (P:'run watch';D:'Watch a run until it completes, showing its progress@@Surveille une ex'#130'cution jus'+
   'qu'''+#133+' sa fin'),
  (P:'search';D:'Search for repositories, issues, and pull requests@@Recherche des d'#130'p'#147'ts, tickets e'+
   't pull requests'),
  (P:'search code';D:'Search within code@@Recherche dans le code'),
  (P:'search commits';D:'Search for commits@@Recherche des commits'),
  (P:'search issues';D:'Search for issues@@Recherche des tickets'),
  (P:'search prs';D:'Search for pull requests@@Recherche des pull requests'),
  (P:'search repos';D:'Search for repositories@@Recherche des d'#130'p'#147'ts'),
  (P:'secret';D:'Manage GitHub secrets@@G'#138're les secrets GitHub'),
  (P:'secret delete';D:'Delete secrets@@Supprime des secrets'),
  (P:'secret list';D:'List secrets@@Liste les secrets'),
  (P:'secret set';D:'Create or update secrets@@Cr'#130'e ou modifie des secrets'),
  (P:'ssh-key';D:'Manage SSH keys@@G'#138're les cl'#130's SSH'),
  (P:'ssh-key add';D:'Add an SSH key to your GitHub account@@Ajoute une cl'#130' SSH '#133' votre compte GitHub'),
  (P:'ssh-key delete';D:'Delete an SSH key from your GitHub account@@Supprime une cl'#130' SSH de votre c'+
   'ompte GitHub'),
  (P:'ssh-key list';D:'Lists SSH keys in your GitHub account@@Liste les cl'#130's SSH de votre compte GitHub'),
  (P:'status';D:'Print information about relevant issues, pull requests, and notifications across repo'+
   'sitories@@Affiche les tickets, pull requests et notifications pertinents de vos d'#130'p'#147'ts'),
  (P:'variable';D:'Manage GitHub Actions variables@@G'#138're les variables de GitHub Actions'),
  (P:'variable delete';D:'Delete variables@@Supprime des variables'),
  (P:'variable get';D:'Get variables@@Affiche une variable'),
  (P:'variable list';D:'List variables@@Liste les variables'),
  (P:'variable set';D:'Create or update variables@@Cr'#130'e ou modifie des variables'),
  (P:'version';D:'Show gh version@@Affiche la version de gh'),
  (P:'workflow';D:'View details about GitHub Actions workflows@@Affiche les d'#130'tails des workflows GitH'+
   'ub Actions'),
  (P:'workflow disable';D:'Disable a workflow@@D'#130'sactive un workflow'),
  (P:'workflow enable';D:'Enable a workflow@@Active un workflow'),
  (P:'workflow list';D:'List workflows@@Liste les workflows'),
  (P:'workflow run';D:'Run a workflow by creating a workflow_dispatch event@@Lance un workflow en cr'#130+
   'ant un '#130'v'#130'nement workflow_dispatch'),
  (P:'workflow view';D:'View the summary of a workflow@@Affiche le r'#130'sum'#130' d''un workflow'));

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
 F:=GetEnv('GH_FORCE_TTY');
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
 CmdAliases,CmdExamples:TSList;
 ODef:Array[0..MaxOpt-1]of TOptDef;
 ONum:LongInt;
 OVals:Array[0..MaxOpt-1]of TSList;
 OSet:Array[0..MaxOpt-1]of Boolean;
 PosArgs:TSList;
 ArgStart:LongInt;
 JsonListing:Boolean;

Procedure CmdBegin(Const Path,Usage:AnsiString);
Var
 I:LongInt;
Begin
 CmdPath:=Path;CmdUsage:=Usage;CmdLongDesc:='';CmdJsonFields:='';
 SClear(CmdAliases);SClear(CmdExamples);
 For I:=0 to MaxOpt-1 do Begin SClear(OVals[I]);OSet[I]:=False;End;
 ONum:=0;SClear(PosArgs);JsonListing:=False;
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

Procedure OptRepo;
Begin
 Opt('repo','R','[HOST/]OWNER/REPO','Select another repository using the [HOST/]OWNER/REPO format@@S'+
   ''+#130+'lectionne un autre d'+#130+'p'+#147+'t au format [H'+#195+#148+'TE/]PROPRI'+#144+'TAIRE/D'+#144+'P'+#195+#148+'T');
End;

Procedure OptJsonAll;
Begin
 Opt('json','','fields','Output JSON with the specified fields@@Produit du JSON avec les champs indiqu'+#130+'s');
 Opt('jq','q','expression','Filter JSON output using a jq expression@@Filtre la sortie JSON avec une expres'+
   'sion jq');
 Opt('template','t','string','Format JSON output using a Go template; see "gh help formatting"@@Formate la s'+
   'ortie JSON avec un mod'+#138+'le Go; voir "gh help formatting"');
End;

Procedure OptWeb(Const What:AnsiString);
Begin
 Opt('web','w','',What);
End;

Procedure OptLimitN(Const What:AnsiString;Def:LongInt);
Begin
 Opt('limit','L','int',What+' (default '+IStr(Def)+')@@'+What+' (d'+#130+'faut '+IStr(Def)+')');
End;

Function HelpLine(Const S:AnsiString):AnsiString;
Begin
 HelpLine:=Tx(S);
End;

Procedure PrintCmdHelp;
Var
 I,W:LongInt;
 Ls:TSList;
 S,D:AnsiString;
 Fl:TSList;
Begin
 D:=DescOf(CmdPath);
 If D<>'' Then WriteLn(D);
 If CmdLongDesc<>'' Then Begin WriteLn;WriteLn(Tx(CmdLongDesc));End;
 WriteLn;
 WriteLn(Lg('USAGE','UTILISATION'));
 WriteLn('  gh ',CmdPath,IfThen_(CmdUsage<>'',' '+CmdUsage,''),IfThen_(ONum>0,' [flags]',''));
 If CmdAliases.N>0 Then Begin
  WriteLn;
  WriteLn(Lg('ALIASES','ALIAS'));
  For I:=0 to CmdAliases.N-1 do Begin
   S:=CmdPath;
   W:=Length(S);
   While(W>0)and(S[W]<>' ')do Dec(W);
   WriteLn('  gh ',Copy(S,1,W),CmdAliases.A[I]);
  End;
 End;
 WriteLn;
 WriteLn(Lg('FLAGS','OPTIONS'));
 SClear(Ls);
 W:=0;
 For I:=0 to ONum-1 do Begin
  If ODef[I].Short<>'' Then S:='-'+ODef[I].Short+', ' Else S:='    ';
  S:=S+'--'+ODef[I].Long;
  If ODef[I].Meta<>'' Then S:=S+' '+ODef[I].Meta;
  SAdd(Ls,S);
  If Length(S)>W Then W:=Length(S);
 End;
 For I:=0 to ONum-1 do WriteLn('  ',PadR(Ls.A[I],W),'   ',Tx(ODef[I].Help));
 WriteLn;
 WriteLn(Lg('INHERITED FLAGS','OPTIONS H'+#144+'RIT'+#144+'ES'));
 WriteLn('      --help   ',Lg('Show help for command','Affiche l''aide de la commande'));
 If CmdJsonFields<>'' Then Begin
  WriteLn;
  WriteLn(Lg('JSON FIELDS','CHAMPS JSON'));
  SplitStr(CmdJsonFields,',',Fl);
  SSort(Fl);
  S:='';
  For I:=0 to Fl.N-1 do Begin
   If S<>'' Then S:=S+', ';
   S:=S+Fl.A[I];
   If Length(S)>70 Then Begin
    If I<Fl.N-1 Then S:=S+',';
    WriteLn('  ',S);
    S:='';
   End;
  End;
  If S<>'' Then WriteLn('  ',S);
 End;
 If CmdExamples.N>0 Then Begin
  WriteLn;
  WriteLn(Lg('EXAMPLES','EXEMPLES'));
  For I:=0 to CmdExamples.N-1 do WriteLn('  ',Tx(CmdExamples.A[I]));
 End;
 WriteLn;
 WriteLn(Lg('LEARN MORE','EN SAVOIR PLUS'));
 WriteLn('  ',Lg('Use `gh <command> <subcommand> --help` for more information about a command.',
   'Utilisez `gh <commande> <sous-commande> --help` pour plus d''informations sur une commande.'));
 WriteLn('  ',Lg('Read the manual at https://cli.github.com/manual',
   'Lisez le manuel '+#133+' https://cli.github.com/manual'));
End;

Procedure FlagErr(Const Msg:AnsiString);
Begin
 WriteLn(StdErr,Msg);
 WriteLn(StdErr);
 WriteLn(StdErr,Lg('Usage:  gh ','Utilisation :  gh '),CmdPath,IfThen_(CmdUsage<>'',' '+CmdUsage,''),
   IfThen_(ONum>0,' [flags]',''));
 WriteLn(StdErr);
 WriteLn(StdErr,Lg('Run ''gh ','Ex'+#130+'cutez ''gh '),CmdPath,Lg(' --help'' for usage.',' --help'' pour l''aide.'));
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
 A,Nm,V:AnsiString;
 Rest:Boolean;
Begin
 Rest:=False;
 I:=First;
 While I<=ParamCount do Begin
  A:=ParamStr(I);
  If Rest Then SAdd(PosArgs,A)
  Else If A='--' Then Rest:=True
  Else If(A='-h')or(A='--help')or(A='/?')Then Begin PrintCmdHelp;Halt(0);End
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
 TmpFile:=DropSlash(D)+DS+'ghpas'+IStr(Random(1000000000))+Tag;
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

Var
 GitRC:LongInt;

{ sortie standard de git, sans la fin de ligne }
Function GitOut(Const Args:AnsiString):AnsiString;
Var
 O:AnsiString;
Begin
 GitRC:=RunCapture('git '+Args+IfThen_(False,'',''),O,False);
 While(O<>'')and(O[Length(O)]in[#10,#13])do Delete(O,Length(O),1);
 GitOut:=O;
End;

{ git attache a la console }
Function GitFg(Const Args:AnsiString):LongInt;
Begin
 GitRC:=RunShell('git '+Args);
 GitFg:=GitRC;
End;

Function WhichCmd(Const Name:AnsiString):AnsiString;
Begin
 {$IFDEF WINDOWS}
 WhichCmd:=FSearch(Name+'.exe',GetEnv('PATH'));
 If WhichCmd='' Then WhichCmd:=FSearch(Name,GetEnv('PATH'));
 {$ELSE}
 WhichCmd:=FSearch(Name,GetEnv('PATH'));
 {$ENDIF}
End;

Var
 ConfigBrowser,ConfigEditor:AnsiString;

Procedure OpenBrowser(Const Url:AnsiString);
Var
 B:AnsiString;
Begin
 B:=GetEnv('GH_BROWSER');
 If B='' Then B:=ConfigBrowser;
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
 Ed:=GetEnv('GH_EDITOR');
 If Ed='' Then Ed:=ConfigEditor;
 If Ed='' Then Ed:=GetEnv('GIT_EDITOR');
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
  P:=Pos(':',Ln);
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
{ Configuration et hotes                                              }
{ ------------------------------------------------------------------ }

Var
 CfgY,HostsY:TYaml;
 CfgLoaded:Boolean;

Function ConfigDir:AnsiString;
Var
 D:AnsiString;
Begin
 D:=GetEnv('GH_CONFIG_DIR');
 If D='' Then D:=GetEnv('XDG_CONFIG_HOME');
 If D<>'' Then Begin
  If GetEnv('GH_CONFIG_DIR')='' Then D:=JoinPath(D,'gh');
 End
 Else Begin
  {$IFDEF WINDOWS}
  D:=GetEnv('AppData');
  If D='' Then D:=JoinPath(HomeDir,'AppData'+DS+'Roaming');
  D:=JoinPath(D,'GitHub CLI');
  {$ELSE}
  D:=JoinPath(JoinPath(HomeDir,'.config'),'gh');
  {$ENDIF}
 End;
 ConfigDir:=DropSlash(D);
End;

Function DataDir:AnsiString;
Var
 D:AnsiString;
Begin
 D:=GetEnv('XDG_DATA_HOME');
 If D='' Then Begin
  {$IFDEF WINDOWS}
  D:=GetEnv('LocalAppData');
  If D='' Then D:=JoinPath(HomeDir,'AppData'+DS+'Local');
  {$ELSE}
  D:=JoinPath(JoinPath(HomeDir,'.local'),'share');
  {$ENDIF}
 End;
 {$IFDEF WINDOWS}
 DataDir:=JoinPath(D,'GitHub CLI');
 {$ELSE}
 DataDir:=JoinPath(D,'gh');
 {$ENDIF}
End;

Function StateDir:AnsiString;
Var
 D:AnsiString;
Begin
 D:=GetEnv('XDG_STATE_HOME');
 If D='' Then Begin
  {$IFDEF WINDOWS}
  D:=GetEnv('LocalAppData');
  If D='' Then D:=JoinPath(HomeDir,'AppData'+DS+'Local');
  {$ELSE}
  D:=JoinPath(JoinPath(HomeDir,'.local'),'state');
  {$ENDIF}
 End;
 {$IFDEF WINDOWS}
 StateDir:=JoinPath(D,'GitHub CLI');
 {$ELSE}
 StateDir:=JoinPath(D,'gh');
 {$ENDIF}
End;

Function ConfigPath:AnsiString;
Begin
 ConfigPath:=JoinPath(ConfigDir,'config.yml');
End;

Function HostsPath:AnsiString;
Begin
 HostsPath:=JoinPath(ConfigDir,'hosts.yml');
End;

Procedure LoadConfig;
Begin
 YamlLoad(ConfigPath,CfgY);
 YamlLoad(HostsPath,HostsY);
 CfgLoaded:=True;
 ConfigBrowser:=YGet(CfgY,'browser');
 ConfigEditor:=YGet(CfgY,'editor');
End;

Procedure SaveConfig;
Begin
 If not YamlSave(ConfigPath,CfgY)Then Die('failed to write '+ConfigPath);
End;

Procedure SaveHosts;
Begin
 If not YamlSave(HostsPath,HostsY)Then Die('failed to write '+HostsPath);
End;

Const
 NCfg=11;
 CfgNames:Array[0..NCfg-1]of AnsiString=('git_protocol','editor','prompt','pager','http_unix_socket',
   'browser','color_labels','accessible_colors','accessible_prompter','spinner','telemetry');
 CfgDefs:Array[0..NCfg-1]of AnsiString=('https','','enabled','','','','disabled','disabled','disabled',
   'enabled','enabled');
 CfgHelp:Array[0..NCfg-1]of AnsiString=(
   'the protocol to use when performing Git operations. Supported values: ssh, https@@le protocole '+
   'utilis'+#130+' pour les op'+#130+'rations Git. Valeurs prises en charge : ssh, https',
   'the text editor program to use for authoring text@@le programme d'''+#130+'dition de texte utilis'+#130+'',
   'toggle interactive prompting in the terminal@@active ou d'+#130+'sactive les invites interactives',
   'the terminal pager program to send standard output to@@le programme de pagination du terminal',
   'the path to a Unix socket through which to make HTTP connection@@le chemin d''un socket Unix pour '+
   'les connexions HTTP',
   'the web browser to use for opening URLs@@le navigateur utilis'+#130+' pour ouvrir les URL',
   'whether to display labels using their RGB hex color codes in terminals that support truecolor@@a'+
   'ffiche les '+#130+'tiquettes avec leur couleur RGB',
   'whether to use a color palette that is accessible@@utilise une palette de couleurs accessible',
   'whether to use a screen reader friendly prompter@@utilise des invites adapt'+#130+'es aux lecteurs d'''+#130+'cran',
   'whether to use animated spinners as a progress indicator@@utilise des indicateurs anim'+#130+'s',
   'enable or disable collection of anonymous usage data@@active ou d'+#130+'sactive la collecte de donn'+#130+'es d'+
   '''utilisation anonymes');

Function CfgDefault(Const Key:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 CfgDefault:='';
 For I:=0 to NCfg-1 do If CfgNames[I]=Key Then CfgDefault:=CfgDefs[I];
End;

Function CfgValid(Const Key:AnsiString):Boolean;
Var
 I:LongInt;
Begin
 CfgValid:=False;
 For I:=0 to NCfg-1 do If CfgNames[I]=Key Then CfgValid:=True;
End;

Function CfgGet(Const Key,Host:AnsiString):AnsiString;
Begin
 If(Host<>'')and YHas(HostsY,Host+'|'+Key)Then Begin CfgGet:=YGet(HostsY,Host+'|'+Key);Exit;End;
 If YHas(CfgY,Key)Then CfgGet:=YGet(CfgY,Key) Else CfgGet:=CfgDefault(Key);
End;

Function IsGithubCom(Const H:AnsiString):Boolean;
Var
 T:AnsiString;
Begin
 T:=LoStr(H);
 IsGithubCom:=(T='github.com')or(T='www.github.com')or EndsWith(T,'.ghe.com')or(T='api.github.com');
End;

{ hote par defaut : GH_HOST, sinon le premier hote connu, sinon github.com }
Function DefaultHost:AnsiString;
Var
 N:TSList;
 I:LongInt;
Begin
 DefaultHost:=GetEnv('GH_HOST');
 If DefaultHost<>'' Then Exit;
 YSub(HostsY,'',N);
 For I:=0 to N.N-1 do If N.A[I]='github.com' Then Begin DefaultHost:='github.com';Exit;End;
 If N.N>0 Then DefaultHost:=N.A[0] Else DefaultHost:='github.com';
End;

Function TokenEnvName(Const Host:AnsiString;Var Src:AnsiString):AnsiString;
Begin
 TokenEnvName:='';
 If IsGithubCom(Host)Then Begin
  If GetEnv('GH_TOKEN')<>'' Then Begin Src:='GH_TOKEN';TokenEnvName:=GetEnv('GH_TOKEN');Exit;End;
  If GetEnv('GITHUB_TOKEN')<>'' Then Begin Src:='GITHUB_TOKEN';TokenEnvName:=GetEnv('GITHUB_TOKEN');Exit;End;
 End
 Else Begin
  If GetEnv('GH_ENTERPRISE_TOKEN')<>'' Then Begin
   Src:='GH_ENTERPRISE_TOKEN';TokenEnvName:=GetEnv('GH_ENTERPRISE_TOKEN');Exit;
  End;
  If GetEnv('GITHUB_ENTERPRISE_TOKEN')<>'' Then Begin
   Src:='GITHUB_ENTERPRISE_TOKEN';TokenEnvName:=GetEnv('GITHUB_ENTERPRISE_TOKEN');Exit;
  End;
 End;
End;

{ jeton de l'hote : variables d'environnement puis hosts.yml }
Function HostToken(Const Host:AnsiString;Var Src:AnsiString):AnsiString;
Var
 T:AnsiString;
Begin
 Src:='';
 T:=TokenEnvName(Host,Src);
 If T<>'' Then Begin HostToken:=T;Exit;End;
 T:=YGet(HostsY,Host+'|oauth_token');
 If T<>'' Then Src:=ConfigPath;
 If T<>'' Then Src:=HostsPath;
 HostToken:=T;
End;

Function TokenOf(Const Host:AnsiString):AnsiString;
Var
 S:AnsiString;
Begin
 TokenOf:=HostToken(Host,S);
End;

{ URL de base de l'API REST (un hote commencant par http:// est utilise tel quel) }
Function ApiBaseOf(Const Host:AnsiString):AnsiString;
Var
 H:AnsiString;
Begin
 H:=LoStr(Host);
 If(H='github.com')or(H='www.github.com')Then ApiBaseOf:='https://api.github.com'
 Else If EndsWith(H,'.ghe.com')Then ApiBaseOf:='https://api.'+H
 Else If StartsWith(H,'http://')or StartsWith(H,'https://')Then ApiBaseOf:=DropSlash(Host)+'/api/v3'
 Else ApiBaseOf:='https://'+H+'/api/v3';
End;

Function GraphqlUrlOf(Const Host:AnsiString):AnsiString;
Var
 H:AnsiString;
Begin
 H:=LoStr(Host);
 If(H='github.com')or(H='www.github.com')Then GraphqlUrlOf:='https://api.github.com/graphql'
 Else If EndsWith(H,'.ghe.com')Then GraphqlUrlOf:='https://api.'+H+'/graphql'
 Else If StartsWith(H,'http://')or StartsWith(H,'https://')Then GraphqlUrlOf:=DropSlash(Host)+'/api/graphql'
 Else GraphqlUrlOf:='https://'+H+'/api/graphql';
End;

Function UploadBaseOf(Const Host:AnsiString):AnsiString;
Var
 H:AnsiString;
Begin
 H:=LoStr(Host);
 If(H='github.com')or(H='www.github.com')Then UploadBaseOf:='https://uploads.github.com'
 Else If EndsWith(H,'.ghe.com')Then UploadBaseOf:='https://uploads.'+H
 Else If StartsWith(H,'http://')or StartsWith(H,'https://')Then UploadBaseOf:=DropSlash(Host)+'/api/uploads'
 Else UploadBaseOf:='https://'+H+'/api/uploads';
End;

{ URL web de l'hote }
Function WebBaseOf(Const Host:AnsiString):AnsiString;
Begin
 If StartsWith(Host,'http://')or StartsWith(Host,'https://')Then WebBaseOf:=DropSlash(Host)
 Else WebBaseOf:='https://'+Host;
End;

Function GitHostName(Const Host:AnsiString):AnsiString;
Var
 P:LongInt;
Begin
 GitHostName:=Host;
 P:=Pos('://',Host);
 If P>0 Then GitHostName:=Copy(Host,P+3,Length(Host));
End;

{ ------------------------------------------------------------------ }
{ Depot courant (remotes git)                                         }
{ ------------------------------------------------------------------ }

Var
 RepoHost,RepoOwner,RepoName:AnsiString;
 RepoResolved:Boolean;

Function RepoFull:AnsiString;
Begin
 RepoFull:=RepoOwner+'/'+RepoName;
End;

Function StripGit(Const S:AnsiString):AnsiString;
Begin
 StripGit:=S;
 If EndsWith(StripGit,'.git')Then Delete(StripGit,Length(StripGit)-3,4);
 While(StripGit<>'')and(StripGit[Length(StripGit)]='/')do Delete(StripGit,Length(StripGit),1);
End;

{ analyse OWNER/REPO, HOST/OWNER/REPO ou une URL ; renvoie False si invalide }
Function ParseRepoRef(Const S:AnsiString;Var Host,Owner,Name:AnsiString):Boolean;
Var
 T:AnsiString;
 L:TSList;
 P:LongInt;
Begin
 ParseRepoRef:=False;
 T:=TrimStr(S);
 Host:='';
 If T='' Then Exit;
 P:=Pos('://',T);
 If P>0 Then Begin
  Host:=Copy(T,1,P+2);
  T:=Copy(T,P+3,Length(T));
  P:=Pos('@',T);
  If(P>0)and(P<Pos('/',T+'/'))Then Delete(T,1,P);
  SplitStr(StripGit(T),'/',L);
  If L.N<3 Then Exit;
  Host:=L.A[0];Owner:=L.A[1];Name:=L.A[2];
  ParseRepoRef:=True;
  Exit;
 End;
 P:=Pos('@',T);
 If(P>0)and(Pos(':',T)>P)Then Begin
  { git@github.com:owner/repo.git }
  Host:=Copy(T,P+1,Pos(':',T)-P-1);
  T:=Copy(T,Pos(':',T)+1,Length(T));
  SplitStr(StripGit(T),'/',L);
  If L.N<2 Then Exit;
  Owner:=L.A[L.N-2];Name:=L.A[L.N-1];
  ParseRepoRef:=True;
  Exit;
 End;
 SplitStr(StripGit(T),'/',L);
 If L.N=2 Then Begin Owner:=L.A[0];Name:=L.A[1];End
 Else If L.N=3 Then Begin Host:=L.A[0];Owner:=L.A[1];Name:=L.A[2];End
 Else Exit;
 If(Owner='')or(Name='')Then Exit;
 ParseRepoRef:=True;
End;

{ remonte les repertoires parents a la recherche de .git }
Function FindGitDir(Var Root:AnsiString):AnsiString;
Var
 D,P,T:AnsiString;
 IsD:Boolean;
 N:LongInt;
Begin
 FindGitDir:='';
 D:=AbsPath('.');
 For N:=1 to 64 do Begin
  P:=JoinPath(D,'.git');
  If PathExists(P,IsD)Then Begin
   Root:=D;
   If IsD Then Begin FindGitDir:=P;Exit;End;
   If ReadAll(P,T)and StartsWith(TrimStr(T),'gitdir:')Then Begin
    T:=TrimStr(Copy(TrimStr(T),8,Length(T)));
    If(Length(T)>0)and(T[1]<>'/')and((Length(T)<2)or(T[2]<>':'))Then T:=JoinPath(D,T);
    FindGitDir:=T;
    Exit;
   End;
  End;
  T:=ParentDir(D);
  If(T='')or(T=D)Then Break;
  D:=T;
 End;
End;

Function GitConfigFile(Const GDir:AnsiString):AnsiString;
Var
 T,C:AnsiString;
Begin
 GitConfigFile:=JoinPath(GDir,'config');
 If not FileExists_(GitConfigFile)Then Begin
  { worktree : commondir }
  If ReadAll(JoinPath(GDir,'commondir'),T)Then Begin
   C:=TrimStr(T);
   If(Length(C)>0)and(C[1]<>'/')Then C:=JoinPath(GDir,C);
   GitConfigFile:=JoinPath(C,'config');
  End;
 End;
End;

Type
 TRemote = Record
  Name,Url,Resolved:AnsiString;
 End;

Var
 Remotes:Array of TRemote;
 NRemotes:LongInt;

Procedure LoadRemotes;
Var
 Root,GDir,Txt,Ln,Sect,Nm,Key,Val:AnsiString;
 L:TSList;
 I,P,K:LongInt;
Begin
 NRemotes:=0;SetLength(Remotes,0);
 GDir:=FindGitDir(Root);
 If GDir='' Then Exit;
 If not ReadAll(GitConfigFile(GDir),Txt)Then Exit;
 SplitStr(ReplaceAll(Txt,#13,''),#10,L);
 Sect:='';
 For I:=0 to L.N-1 do Begin
  Ln:=TrimStr(L.A[I]);
  If Ln='' Then Continue;
  If Ln[1]='[' Then Begin
   Sect:='';
   If StartsWith(Ln,'[remote "')Then Begin
    P:=Pos('"',Copy(Ln,10,Length(Ln)));
    If P>0 Then Sect:=Copy(Ln,10,P-1);
    If Sect<>'' Then Begin
     SetLength(Remotes,NRemotes+1);
     Remotes[NRemotes].Name:=Sect;Remotes[NRemotes].Url:='';Remotes[NRemotes].Resolved:='';
     Inc(NRemotes);
    End;
   End;
   Continue;
  End;
  If(Sect<>'')and(Ln[1]<>'#')and(Ln[1]<>';')Then Begin
   P:=Pos('=',Ln);
   If P=0 Then Continue;
   Key:=LoStr(TrimStr(Copy(Ln,1,P-1)));
   Val:=TrimStr(Copy(Ln,P+1,Length(Ln)));
   For K:=0 to NRemotes-1 do If Remotes[K].Name=Sect Then Begin
    If Key='url' Then Remotes[K].Url:=Val
    Else If Key='gh-resolved' Then Remotes[K].Resolved:=Val;
   End;
  End;
 End;
End;

Function RemotePrio(Const N:AnsiString):LongInt;
Begin
 If N='upstream' Then RemotePrio:=0 Else If N='github' Then RemotePrio:=1
 Else If N='origin' Then RemotePrio:=2 Else RemotePrio:=3;
End;

{ choisit le remote de reference ; renvoie son indice ou -1 }
Function BaseRemote:LongInt;
Var
 I,Best,BP:LongInt;
 H,O,N:AnsiString;
Begin
 BaseRemote:=-1;
 LoadRemotes;
 Best:=-1;BP:=99;
 For I:=0 to NRemotes-1 do If Remotes[I].Resolved='base' Then Begin BaseRemote:=I;Exit;End;
 For I:=0 to NRemotes-1 do
  If ParseRepoRef(Remotes[I].Url,H,O,N)and(H<>'')Then
   If RemotePrio(Remotes[I].Name)<BP Then Begin Best:=I;BP:=RemotePrio(Remotes[I].Name);End;
 BaseRemote:=Best;
End;

{ determine le depot cible : --repo, GH_REPO, puis remotes git }
Function ResolveRepo(Required:Boolean):Boolean;
Var
 S,H,O,N:AnsiString;
 I:LongInt;
Begin
 ResolveRepo:=False;
 If RepoResolved Then Begin ResolveRepo:=True;Exit;End;
 S:=OptGet('repo');
 If S='' Then S:=GetEnv('GH_REPO');
 If S<>'' Then Begin
  If not ParseRepoRef(S,H,O,N)Then
    Die2('expected the "[HOST/]OWNER/REPO" format, got "'+S+'"',1);
  If H='' Then H:=DefaultHost;
  RepoHost:=H;RepoOwner:=O;RepoName:=N;RepoResolved:=True;
  ResolveRepo:=True;Exit;
 End;
 I:=BaseRemote;
 If I>=0 Then Begin
  ParseRepoRef(Remotes[I].Url,H,O,N);
  RepoHost:=H;RepoOwner:=O;RepoName:=N;RepoResolved:=True;
  ResolveRepo:=True;Exit;
 End;
 If Required Then Begin
  If NRemotes=0 Then
    Die2('failed to run git: not a git repository'#10'unable to determine the current repository. Use `-R OWNER/REPO` or run this command from a git repository.',1)
  Else Die2('none of the git remotes configured for this repository point to a known GitHub host. To tell gh about a new GitHub host, please use `gh auth login`',1);
 End;
End;

Function CurrentBranch:AnsiString;
Var
 Root,GDir,T:AnsiString;
Begin
 CurrentBranch:='';
 GDir:=FindGitDir(Root);
 If GDir='' Then Exit;
 If ReadAll(JoinPath(GDir,'HEAD'),T)Then Begin
  T:=TrimStr(T);
  If StartsWith(T,'ref: refs/heads/')Then CurrentBranch:=Copy(T,17,Length(T));
 End;
End;

Function InGitRepo:Boolean;
Var
 Root:AnsiString;
Begin
 InGitRepo:=FindGitDir(Root)<>'';
End;
{ ------------------------------------------------------------------ }
{ Listes d'entiers, constructeurs JSON                                }
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

Function JStrOrNull(Const S:AnsiString):AnsiString;
Begin
 If S='' Then JStrOrNull:='null' Else JStrOrNull:=JQ(S);
End;

{ ------------------------------------------------------------------ }
{ Dates                                                               }
{ ------------------------------------------------------------------ }

{ "2024-05-06T07:08:09Z" -> secondes depuis 1970 (0 si invalide) }
Function IsoToEpoch(Const S:AnsiString):Int64;
Var
 Y,M,D,H,Mi,Se:LongInt;
 Z:Int64;
 P:LongInt;
 Tz:AnsiString;
Begin
 IsoToEpoch:=0;
 If Length(S)<10 Then Exit;
 Y:=ToInt(Copy(S,1,4),-1);M:=ToInt(Copy(S,6,2),-1);D:=ToInt(Copy(S,9,2),-1);
 If(Y<0)or(M<0)or(D<0)Then Exit;
 H:=0;Mi:=0;Se:=0;
 If Length(S)>=19 Then Begin
  H:=ToInt(Copy(S,12,2),0);Mi:=ToInt(Copy(S,15,2),0);Se:=ToInt(Copy(S,18,2),0);
 End;
 Z:=DaysFromCivil(Y,M,D)*86400+H*3600+Mi*60+Se;
 If Length(S)>19 Then Begin
  Tz:=Copy(S,20,Length(S));
  P:=Pos('+',Tz);
  If P>0 Then Z:=Z-(ToInt(Copy(Tz,P+1,2),0)*3600+ToInt(Copy(Tz,P+4,2),0)*60);
  P:=Pos('-',Tz);
  If P>0 Then Z:=Z+(ToInt(Copy(Tz,P+1,2),0)*3600+ToInt(Copy(Tz,P+4,2),0)*60);
 End;
 IsoToEpoch:=Z;
End;

Function EpochToIso(E:Int64):AnsiString;
Var
 S:AnsiString;
Begin
 S:=StampToStr(E);
 EpochToIso:=Copy(S,1,10)+'T'+Copy(S,12,8)+'Z';
End;

Function Pluralize(N:Int64;Const U:AnsiString):AnsiString;
Begin
 If N=1 Then Pluralize:='1 '+U Else Pluralize:=IStr(N)+' '+U+'s';
End;

{ "about 3 hours ago" }
Function FuzzyAgo(Secs:Int64):AnsiString;
Begin
 If Secs<60 Then FuzzyAgo:='less than a minute ago'
 Else If Secs<3600 Then FuzzyAgo:='about '+Pluralize(Secs div 60,'minute')+' ago'
 Else If Secs<86400 Then FuzzyAgo:='about '+Pluralize(Secs div 3600,'hour')+' ago'
 Else If Secs<86400*30 Then FuzzyAgo:='about '+Pluralize(Secs div 86400,'day')+' ago'
 Else If Secs<86400*365 Then FuzzyAgo:='about '+Pluralize(Secs div(86400*30),'month')+' ago'
 Else FuzzyAgo:='about '+Pluralize(Secs div(86400*365),'year')+' ago';
End;

{ date d'une liste : relative sur un terminal, ISO sinon }
Function TimeCell(Const Iso:AnsiString):AnsiString;
Begin
 If Iso='' Then Begin TimeCell:='';Exit;End;
 If OutTTY Then TimeCell:=FuzzyAgo(NowEpoch-IsoToEpoch(Iso)) Else TimeCell:=Iso;
End;

Function FmtSize(N:Int64):AnsiString;
Var
 D:Double;
 U:LongInt;
 S:AnsiString;
Const
 Un:Array[0..4]of AnsiString=('B','KiB','MiB','GiB','TiB');
Begin
 If N<1024 Then Begin FmtSize:=IStr(N)+' B';Exit;End;
 D:=N;U:=0;
 While(D>=1024)and(U<4)do Begin D:=D/1024;Inc(U);End;
 Str(D:0:2,S);
 FmtSize:=S+' '+Un[U];
End;

{ ------------------------------------------------------------------ }
{ Acces a l'API GitHub                                                }
{ ------------------------------------------------------------------ }

Var
 ApiHost:AnsiString;
 AllowAnon:Boolean;
 LastRateInfo:AnsiString;

Function ApiUrl(Const Path:AnsiString):AnsiString;
Begin
 If StartsWith(Path,'http://')or StartsWith(Path,'https://')Then ApiUrl:=Path
 Else If StartsWith(Path,'/')Then ApiUrl:=ApiBaseOf(ApiHost)+Path
 Else ApiUrl:=ApiBaseOf(ApiHost)+'/'+Path;
End;

Procedure RequireAuth;
Begin
 If AllowAnon Then Exit;
 If TokenOf(ApiHost)='' Then Begin
  WriteLn(StdErr,Lg('To get started with GitHub CLI, please run:  gh auth login',
    'Pour commencer avec GitHub CLI, ex'+#130+'cutez :  gh auth login'));
  WriteLn(StdErr,Lg('Alternatively, populate the GH_TOKEN environment variable with a GitHub API '+
    'authentication token.','Sinon, d'+#130+'finissez la variable d''environnement GH_TOKEN avec un jeton '+
    'd''authentification de l''API GitHub.'));
  Halt(4);
 End;
End;

Procedure ApiCall(Var R:THttpReq;Const Method,Path,Body:AnsiString);
Begin
 RequireAuth;
 ReqInit(R,Method,ApiUrl(Path),TokenOf(ApiHost));
 If Body<>'' Then Begin
  R.BodyStr:=Body;
  R.Headers:='Content-Type: application/json'#13#10;
 End;
 HttpDo(R);
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
  410:ReasonOf:='Gone';
  422:ReasonOf:='Unprocessable Entity';
  429:ReasonOf:='Too Many Requests';
  500:ReasonOf:='Internal Server Error';
  502:ReasonOf:='Bad Gateway';
  503:ReasonOf:='Service Unavailable';
  504:ReasonOf:='Gateway Timeout';
  Else ReasonOf:='HTTP error';
 End;
End;

{ message d'erreur a la maniere de gh }
Function ErrText(Var R:THttpReq):AnsiString;
Var
 J,E,C:LongInt;
 Msg,Det:AnsiString;
Begin
 If R.Status=0 Then Begin ErrText:=R.Err;Exit;End;
 Msg:='';Det:='';
 J:=JParse(R.RespBody);
 If J>=0 Then Begin
  Msg:=JS(J,'message');
  E:=JGet(J,'errors');
  If(E>=0)and(JP[E].Kind=JK_ARR)Then Begin
   C:=JP[E].First;
   While C>=0 do Begin
    If JP[C].Kind=JK_STR Then Det:=Det+#10+JP[C].S
    Else If JS(C,'message')<>'' Then Det:=Det+#10+JS(C,'message')
    Else If JS(C,'code')<>'' Then Det:=Det+#10+JS(C,'resource')+' '+JS(C,'field')+' '+JS(C,'code');
    C:=JP[C].Next;
   End;
  End;
 End;
 If Msg='' Then Msg:=ReasonOf(R.Status);
 ErrText:='HTTP '+IStr(R.Status)+': '+Msg+' ('+R.Url+')'+Det;
 If R.Status=401 Then ErrText:=ErrText+#10'Try authenticating with:  gh auth login';
 If(R.Status=403)and(Pos('rate limit',LoStr(Msg))>0)Then
   ErrText:=ErrText+#10'To increase the rate limit, authenticate with:  gh auth login';
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
 If ApiJ<0 Then Die('invalid JSON response from '+R.Url);
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

Function LinkNext(Const H:AnsiString):AnsiString;
Var
 V:AnsiString;
 P,Q:LongInt;
Begin
 LinkNext:='';
 V:=HeaderGet(H,'link');
 P:=Pos('rel="next"',V);
 If P=0 Then Exit;
 Q:=P;
 While(Q>0)and(V[Q]<>'<')do Dec(Q);
 If Q=0 Then Exit;
 P:=Pos('>',Copy(V,Q,Length(V)));
 If P>0 Then LinkNext:=Copy(V,Q+1,P-2);
End;

Function WithQuery(Const Path,Q_:AnsiString):AnsiString;
Begin
 If Q_='' Then WithQuery:=Path
 Else If Pos('?',Path)>0 Then WithQuery:=Path+'&'+Q_
 Else WithQuery:=Path+'?'+Q_;
End;

{ liste paginee : Key = champ contenant le tableau ('' si la reponse est un tableau) }
Procedure ApiPaged(Const Path:AnsiString;Limit:LongInt;Const Key:AnsiString;Var L:TIList;
  Var Total:Int64);
Var
 R:THttpReq;
 Url:AnsiString;
 J,Arr,C:LongInt;
 Per:LongInt;
Begin
 L.N:=0;SetLength(L.A,0);Total:=-1;
 Per:=100;
 If(Limit>0)and(Limit<100)Then Per:=Limit;
 Url:=WithQuery(Path,'per_page='+IStr(Per));
 While Url<>'' do Begin
  ApiMust(R,'GET',Url,'');
  J:=JParse(R.RespBody);
  If J<0 Then Die('invalid JSON response from '+R.Url);
  If Key<>'' Then Begin
   Arr:=JGet(J,Key);
   If JGet(J,'total_count')>=0 Then Total:=JI(J,'total_count');
  End
  Else Arr:=J;
  If(Arr>=0)and(JP[Arr].Kind=JK_ARR)Then Begin
   C:=JP[Arr].First;
   While C>=0 do Begin
    IAdd(L,C);
    If(Limit>0)and(L.N>=Limit)Then Exit;
    C:=JP[C].Next;
   End;
  End;
  Url:=LinkNext(R.RespHeaders);
 End;
End;

Procedure ApiPagedQ(Const Path:AnsiString;Limit:LongInt;Const Key:AnsiString;Var L:TIList);
Var
 T:Int64;
Begin
 ApiPaged(Path,Limit,Key,L,T);
End;

{ GraphQL : renvoie le noeud "data" ; arrete le programme sur erreur }
Function Gql(Const Query,VarsJson:AnsiString):LongInt;
Var
 R:THttpReq;
 B:AnsiString;
 J,E:LongInt;
Begin
 RequireAuth;
 B:='{"query":'+JQ(Query);
 If VarsJson<>'' Then B:=B+',"variables":'+VarsJson;
 B:=B+'}';
 ReqInit(R,'POST',GraphqlUrlOf(ApiHost),TokenOf(ApiHost));
 R.BodyStr:=B;
 R.Headers:='Content-Type: application/json'#13#10;
 HttpDo(R);
 If R.Err<>'' Then Die(R.Err);
 J:=JParse(R.RespBody);
 If J<0 Then Begin
  If not ApiOk(R)Then Die(ErrText(R));
  Die('invalid JSON response from '+R.Url);
 End;
 E:=JGet(J,'errors');
 If(E>=0)and(JP[E].Cnt>0)Then Begin
  If JGet(J,'data')>=0 Then Begin
   If JP[JGet(J,'data')].Kind<>JK_NULL Then Begin
    Gql:=JGet(J,'data');
    { erreurs partielles : message sur stderr }
    WriteLn(StdErr,'GraphQL: ',JS(JP[E].First,'message'));
    Exit;
   End;
  End;
  Die('GraphQL: '+JS(JP[E].First,'message'));
 End;
 If not ApiOk(R)Then Die(ErrText(R));
 Gql:=JGet(J,'data');
End;

{ ------------------------------------------------------------------ }
{ Champs --json : table de correspondance REST -> JSON de gh          }
{ ------------------------------------------------------------------ }

Type
 TFieldHook = Function(Node:LongInt;Const F:AnsiString;Var Out_:AnsiString):Boolean;

Var
 JFields:TSList;
 UseJson:Boolean;
 JqExpr,TmplText:AnsiString;

Function FieldWanted(Const F:AnsiString):Boolean;
Begin
 FieldWanted:=UseJson and(SIndex(JFields,F)>=0);
End;

Function UserJson(U:LongInt):AnsiString;
Var
 L:TSList;
 Lg_:AnsiString;
Begin
 If(U<0)or(JP[U].Kind<>JK_OBJ)Then Begin UserJson:='null';Exit;End;
 SClear(L);
 FS(L,'id',JS(U,'node_id'));
 FB(L,'is_bot',JS(U,'type')='Bot');
 Lg_:=JS(U,'login');
 FS(L,'login',Lg_);
 FS(L,'name',JS(U,'name'));
 UserJson:=ObjOf(L);
End;

Function UsersJson(A:LongInt):AnsiString;
Var
 L:TSList;
 C:LongInt;
Begin
 SClear(L);
 If A>=0 Then Begin
  C:=JP[A].First;
  While C>=0 do Begin SAdd(L,UserJson(C));C:=JP[C].Next;End;
 End;
 UsersJson:='['+JoinList(L,',')+']';
End;

Function LabelsJson(A:LongInt):AnsiString;
Var
 L,O:TSList;
 C:LongInt;
Begin
 SClear(L);
 If A>=0 Then Begin
  C:=JP[A].First;
  While C>=0 do Begin
   SClear(O);
   FS(O,'id',JS(C,'node_id'));
   FS(O,'name',JS(C,'name'));
   FS(O,'description',JS(C,'description'));
   FS(O,'color',JS(C,'color'));
   SAdd(L,ObjOf(O));
   C:=JP[C].Next;
  End;
 End;
 LabelsJson:='['+JoinList(L,',')+']';
End;

Function MilestoneJson(M:LongInt):AnsiString;
Var
 O:TSList;
Begin
 If(M<0)or(JP[M].Kind<>JK_OBJ)Then Begin MilestoneJson:='null';Exit;End;
 SClear(O);
 FS(O,'description',JS(M,'description'));
 FS(O,'dueOn',JS(M,'due_on'));
 FN(O,'number',JI(M,'number'));
 FS(O,'title',JS(M,'title'));
 MilestoneJson:=ObjOf(O);
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

{ Spec : "nomGh=chemin.rest:genre;..." ; genres :
   s chaine, n nombre, b booleen, S chaine en majuscules, N chaine ou null, u utilisateur,
   U utilisateurs, L etiquettes, m jalon, R copie brute, c nombre d'elements, z JSON litteral,
   C ferme (state=closed), X motif de fermeture, Z compteur {totalCount} }
Function ShapeField(Node:LongInt;Const Spec,F:AnsiString;Hook:TFieldHook;Var Out_:AnsiString):Boolean;
Var
 L:TSList;
 I,P,Q,N:LongInt;
 Ent,Nm,Path,Kd:AnsiString;
 V:LongInt;
Begin
 ShapeField:=False;
 If Assigned(Hook)Then
  If Hook(Node,F,Out_)Then Begin ShapeField:=True;Exit;End;
 SplitStr(Spec,';',L);
 For I:=0 to L.N-1 do Begin
  Ent:=L.A[I];
  P:=Pos('=',Ent);
  If P=0 Then Continue;
  Nm:=Copy(Ent,1,P-1);
  If Nm<>F Then Continue;
  Q:=Length(Ent);
  While(Q>P)and(Ent[Q]<>':')do Dec(Q);
  Path:=Copy(Ent,P+1,Q-P-1);
  Kd:=Copy(Ent,Q+1,Length(Ent));
  If Kd='z' Then Begin Out_:=Path;ShapeField:=True;Exit;End;
  V:=JPath(Node,Path);
  If Kd='s' Then Out_:=JQ(JTxt(V))
  Else If Kd='S' Then Out_:=JQ(UpStr(JTxt(V)))
  Else If Kd='N' Then Begin
   If(V<0)or(JP[V].Kind=JK_NULL)Then Out_:='null' Else Out_:=JQ(JTxt(V));
  End
  Else If Kd='n' Then Begin
   If(V<0)or(JP[V].Kind<>JK_NUM)Then Out_:='0' Else Out_:=JP[V].S;
  End
  Else If Kd='b' Then Out_:=JBool(JTxt(V)='true')
  Else If Kd='u' Then Out_:=UserJson(V)
  Else If Kd='U' Then Out_:=UsersJson(V)
  Else If Kd='L' Then Out_:=LabelsJson(V)
  Else If Kd='m' Then Out_:=MilestoneJson(V)
  Else If Kd='R' Then Begin
   If V<0 Then Out_:='null' Else Out_:=RawJson(V);
  End
  Else If Kd='c' Then Begin
   If V<0 Then N:=0 Else N:=JP[V].Cnt;
   Out_:=IStr(N);
  End
  Else If Kd='Z' Then Begin
   If(V>=0)and(JP[V].Kind=JK_NUM)Then N:=JI(Node,Path)
   Else If V>=0 Then N:=JP[V].Cnt Else N:=0;
   Out_:='{"totalCount":'+IStr(N)+'}';
  End
  Else If Kd='C' Then Out_:=JBool(LoStr(JTxt(V))='closed')
  Else If Kd='X' Then Begin
   Nm:=UpStr(JTxt(V));
   Out_:=JQ(Nm);
  End
  Else Out_:='null';
  ShapeField:=True;
  Exit;
 End;
End;

{ objet JSON avec les champs demandes, tries par nom }
Function ShapeObj(Node:LongInt;Const Spec:AnsiString;Hook:TFieldHook):AnsiString;
Var
 L:TSList;
 I:LongInt;
 Out_:AnsiString;
Begin
 SClear(L);
 For I:=0 to JFields.N-1 do Begin
  Out_:='null';
  ShapeField(Node,Spec,JFields.A[I],Hook,Out_);
  SAdd(L,JQ(JFields.A[I])+':'+Out_);
 End;
 ShapeObj:='{'+JoinList(L,',')+'}';
End;

{ liste des noms de champs declares dans Spec }
Function SpecNames(Const Spec:AnsiString):AnsiString;
Var
 L:TSList;
 I,P:LongInt;
 R:AnsiString;
Begin
 SplitStr(Spec,';',L);
 R:='';
 For I:=0 to L.N-1 do Begin
  P:=Pos('=',L.A[I]);
  If P>1 Then Begin
   If R<>'' Then R:=R+',';
   R:=R+Copy(L.A[I],1,P-1);
  End;
 End;
 SpecNames:=R;
End;

{ valide --json / --jq / --template apres ParseArgs ; renseigne UseJson et JFields }
Procedure JsonSetup(Const AllFields:AnsiString);
Var
 All,Req:TSList;
 I,J:LongInt;
Begin
 UseJson:=False;SClear(JFields);
 JqExpr:=OptGet('jq');TmplText:=OptGet('template');
 If JsonListing or(OptHas('json')and(OptGet('json')=''))Then Begin
  SplitStr(AllFields,',',All);SSort(All);
  WriteLn(StdErr,'Specify one or more comma-separated fields for `--json`:');
  For I:=0 to All.N-1 do WriteLn(StdErr,'  ',All.A[I]);
  Halt(1);
 End;
 If not OptHas('json')Then Begin
  If JqExpr<>'' Then Die2('cannot use `--jq` without specifying `--json`',1);
  If TmplText<>'' Then Die2('cannot use `--template` without specifying `--json`',1);
  Exit;
 End;
 If(JqExpr<>'')and(TmplText<>'')Then Die2('cannot use `--jq` and `--template` at the same time',1);
 SplitStr(OptGet('json'),',',Req);
 SplitStr(AllFields,',',All);SSort(All);
 For I:=0 to Req.N-1 do Begin
  Req.A[I]:=TrimStr(Req.A[I]);
  If Req.A[I]='' Then Continue;
  If SIndex(All,Req.A[I])<0 Then Begin
   WriteLn(StdErr,'Unknown JSON field: "',Req.A[I],'"');
   WriteLn(StdErr,'Available fields:');
   For J:=0 to All.N-1 do WriteLn(StdErr,'  ',All.A[J]);
   Halt(1);
  End;
  If SIndex(JFields,Req.A[I])<0 Then SAdd(JFields,Req.A[I]);
 End;
 SSort(JFields);
 UseJson:=True;
End;

{ ------------------------------------------------------------------ }
{ Tableaux                                                            }
{ ------------------------------------------------------------------ }

Var
 TblHead:AnsiString;
 TblRows:TSList;

{ Head='' : pas d'en-tete ; l'en-tete n'est affiche que sur un terminal }
Procedure TblBegin(Const Head:AnsiString);
Begin
 TblHead:=Head;
 SClear(TblRows);
End;

Procedure TblRow(Const Cells:AnsiString);
Begin
 SAdd(TblRows,ReplaceAll(ReplaceAll(Cells,#13,''),#10,' '));
End;

Procedure TblPrint;
Var
 Cols:LongInt;
 W:Array[0..23]of LongInt;
 H,Cell:TSList;
 I,J,Tot,Big:LongInt;
 Line:AnsiString;
 Rows:Array of TSList;
Begin
 If not OutTTY Then Begin
  For I:=0 to TblRows.N-1 do WriteLn(TblRows.A[I]);
  Exit;
 End;
 SplitStr(TblHead,#9,H);
 Cols:=1;
 SetLength(Rows,TblRows.N);
 For I:=0 to TblRows.N-1 do Begin
  SplitStr(TblRows.A[I],#9,Rows[I]);
  If Rows[I].N>Cols Then Cols:=Rows[I].N;
 End;
 If(TblHead<>'')and(H.N>Cols)Then Cols:=H.N;
 If Cols>24 Then Cols:=24;
 For I:=0 to Cols-1 do W[I]:=0;
 If TblHead<>'' Then For I:=0 to H.N-1 do If(I<Cols)and(DispLen(H.A[I])>W[I])Then W[I]:=DispLen(H.A[I]);
 For I:=0 to TblRows.N-1 do
  For J:=0 to Rows[I].N-1 do If(J<Cols)and(DispLen(Rows[I].A[J])>W[J])Then W[J]:=DispLen(Rows[I].A[J]);
 { reduit la plus large colonne pour tenir dans le terminal }
 Repeat
  Tot:=(Cols-1)*2;
  Big:=0;
  For I:=0 to Cols-1 do Begin Inc(Tot,W[I]);If W[I]>W[Big]Then Big:=I;End;
  If(Tot>TermWidth)and(W[Big]>12)Then Dec(W[Big],Tot-TermWidth) Else Break;
  If W[Big]<12 Then W[Big]:=12;
 Until False;
 If TblHead<>'' Then Begin
  Line:='';
  For I:=0 to Cols-1 do Begin
   If I<H.N Then Line:=Line+PadD(H.A[I],W[I]) Else Line:=Line+PadD('',W[I]);
   If I<Cols-1 Then Line:=Line+'  ';
  End;
  WriteLn(TrimRight_(Line));
 End;
 For I:=0 to TblRows.N-1 do Begin
  Line:='';
  For J:=0 to Cols-1 do Begin
   If J<Rows[I].N Then Line:=Line+PadD(Trunc_(Rows[I].A[J],W[J]),W[J]) Else Line:=Line+PadD('',W[J]);
   If J<Cols-1 Then Line:=Line+'  ';
  End;
  WriteLn(TrimRight_(Line));
 End;
End;

{ en-tete "Showing X of Y things in repo" affiche seulement sur un terminal }
Procedure ShowingLine(Shown,Total:LongInt;Const What,Where:AnsiString);
Begin
 If not OutTTY Then Exit;
 WriteLn('Showing ',Shown,' of ',Total,' ',What,IfThen_(Where<>'',' in '+Where,''));
 WriteLn;
End;
{ ------------------------------------------------------------------ }
{ Expressions regulieres (retour arriere) pour jq et les modeles       }
{ ------------------------------------------------------------------ }

Const
 RX_CHAR=1; RX_ANY=2; RX_CLASS=3; RX_SPLIT=4; RX_JMP=5; RX_SAVE=6; RX_BOL=7; RX_EOL=8;
 RX_WORDB=9; RX_NWORDB=10; RX_MATCH=11;

Type
 TCharSet = Set of Char;
 TRxIns = Record
  Op:Byte;
  C:Char;
  X,Y:LongInt;
  Neg:Boolean;
  Set_:TCharSet;
 End;

Var
 RxP:Array of TRxIns;
 RxN:LongInt;
 RxSrc:AnsiString;
 RxPos:LongInt;
 RxIcase,RxErr:Boolean;
 RxNGroups:LongInt;
 RxCap:Array[0..19]of LongInt;
 RxStr:AnsiString;
 RxSteps:LongInt;
 RxGroupNames:Array[0..9]of AnsiString;

Function RxEmit(Op:Byte):LongInt;
Begin
 If RxN>=Length(RxP)Then SetLength(RxP,Length(RxP)*2+32);
 FillChar(RxP[RxN],SizeOf(RxP[RxN]),0);
 RxP[RxN].Op:=Op;
 RxEmit:=RxN;
 Inc(RxN);
End;

Procedure RxAlt;forward;

Function RxEscSet(C:Char;Var S:TCharSet):Boolean;
Var
 I:LongInt;
Begin
 RxEscSet:=True;
 S:=[];
 Case C of
  'd':S:=['0'..'9'];
  'D':Begin For I:=0 to 255 do If not(Chr(I)in['0'..'9'])Then S:=S+[Chr(I)];End;
  'w':S:=['a'..'z','A'..'Z','0'..'9','_'];
  'W':Begin For I:=0 to 255 do If not(Chr(I)in['a'..'z','A'..'Z','0'..'9','_'])Then S:=S+[Chr(I)];End;
  's':S:=[' ',#9,#10,#13,#11,#12];
  'S':Begin For I:=0 to 255 do If not(Chr(I)in[' ',#9,#10,#13,#11,#12])Then S:=S+[Chr(I)];End;
  Else RxEscSet:=False;
 End;
End;

Function RxEscChar(C:Char):Char;
Begin
 Case C of
  'n':RxEscChar:=#10;
  't':RxEscChar:=#9;
  'r':RxEscChar:=#13;
  'f':RxEscChar:=#12;
  'v':RxEscChar:=#11;
  Else RxEscChar:=C;
 End;
End;

{ compile un atome et renvoie l'indice de la premiere instruction }
Procedure RxAtom;
Var
 C,D:Char;
 I:LongInt;
 S:TCharSet;
 Neg:Boolean;
 G:LongInt;
 Lo:Char;
Begin
 C:=RxSrc[RxPos];
 Inc(RxPos);
 Case C of
  '.':RxEmit(RX_ANY);
  '^':RxEmit(RX_BOL);
  '$':RxEmit(RX_EOL);
  '(':Begin
       If(RxPos+1<=Length(RxSrc))and(RxSrc[RxPos]='?')and(RxSrc[RxPos+1]=':')Then Begin
        Inc(RxPos,2);
        RxAlt;
       End
       Else Begin
        If(RxPos+1<=Length(RxSrc))and(RxSrc[RxPos]='?')and(RxSrc[RxPos+1]='<')Then Begin
         Inc(RxPos,2);
         I:=RxPos;
         While(RxPos<=Length(RxSrc))and(RxSrc[RxPos]<>'>')do Inc(RxPos);
         G:=RxNGroups+1;
         If G<=9 Then RxGroupNames[G]:=Copy(RxSrc,I,RxPos-I);
         Inc(RxPos);
        End;
        Inc(RxNGroups);
        G:=RxNGroups;
        I:=RxEmit(RX_SAVE);RxP[I].X:=G*2;
        RxAlt;
        I:=RxEmit(RX_SAVE);RxP[I].X:=G*2+1;
       End;
       If(RxPos>Length(RxSrc))or(RxSrc[RxPos]<>')')Then RxErr:=True Else Inc(RxPos);
      End;
  '[':Begin
       Neg:=False;S:=[];
       If(RxPos<=Length(RxSrc))and(RxSrc[RxPos]='^')Then Begin Neg:=True;Inc(RxPos);End;
       I:=0;
       While RxPos<=Length(RxSrc)do Begin
        C:=RxSrc[RxPos];
        If(C=']')and(I>0)Then Break;
        Inc(RxPos);Inc(I);
        If(C='[')and(RxPos<=Length(RxSrc))and(RxSrc[RxPos]=':')Then Begin
         { classes POSIX }
         G:=Pos(':]',Copy(RxSrc,RxPos,Length(RxSrc)));
         If G>0 Then Begin
          D:=#0;
          Case Copy(RxSrc,RxPos+1,G-2)[1] of
           'a':If Copy(RxSrc,RxPos+1,G-2)='alpha' Then S:=S+['a'..'z','A'..'Z']
               Else S:=S+['a'..'z','A'..'Z','0'..'9'];
           'd':S:=S+['0'..'9'];
           's':S:=S+[' ',#9,#10,#13];
           'u':S:=S+['A'..'Z'];
           'l':S:=S+['a'..'z'];
           'p':S:=S+['!'..'/',':'..'@','['..'`','{'..'~'];
           'w':S:=S+['a'..'z','A'..'Z','0'..'9','_'];
          End;
          Inc(RxPos,G+1);
          Continue;
         End;
        End;
        If C='\' Then Begin
         If RxPos>Length(RxSrc)Then Break;
         D:=RxSrc[RxPos];Inc(RxPos);
         If RxEscSet(D,S)Then Begin
          Case D of
           'd':S:=S+['0'..'9'];
           'w':S:=S+['a'..'z','A'..'Z','0'..'9','_'];
           's':S:=S+[' ',#9,#10,#13,#11,#12];
          End;
         End
         Else S:=S+[RxEscChar(D)];
         Continue;
        End;
        Lo:=C;
        If(RxPos+1<=Length(RxSrc))and(RxSrc[RxPos]='-')and(RxSrc[RxPos+1]<>']')Then Begin
         D:=RxSrc[RxPos+1];
         Inc(RxPos,2);
         For C:=Lo to D do S:=S+[C];
        End
        Else S:=S+[Lo];
       End;
       If(RxPos>Length(RxSrc))Then RxErr:=True Else Inc(RxPos);
       If RxIcase Then Begin
        For C:='a' to 'z' do If(C in S)or(UpCase(C)in S)Then S:=S+[C,UpCase(C)];
       End;
       I:=RxEmit(RX_CLASS);RxP[I].Neg:=Neg;RxP[I].Set_:=S;
      End;
  '\':Begin
       If RxPos>Length(RxSrc)Then Begin RxErr:=True;Exit;End;
       D:=RxSrc[RxPos];Inc(RxPos);
       If D='b' Then RxEmit(RX_WORDB)
       Else If D='B' Then RxEmit(RX_NWORDB)
       Else If RxEscSet(D,S)Then Begin
        I:=RxEmit(RX_CLASS);RxP[I].Neg:=False;RxP[I].Set_:=S;
       End
       Else Begin
        I:=RxEmit(RX_CHAR);RxP[I].C:=RxEscChar(D);
       End;
      End;
  Else Begin
   I:=RxEmit(RX_CHAR);RxP[I].C:=C;
  End;
 End;
End;

{ re-emet un fragment de code relocalise (Old = indice d'origine) }
Procedure RxCopy(Const Code:Array of TRxIns;Ln,Old:LongInt);
Var
 K,I,Base:LongInt;
Begin
 Base:=RxN;
 For K:=0 to Ln-1 do Begin
  I:=RxEmit(Code[K].Op);
  RxP[I]:=Code[K];
  If Code[K].Op=RX_JMP Then RxP[I].X:=Code[K].X-Old+Base
  Else If Code[K].Op=RX_SPLIT Then Begin
   RxP[I].X:=Code[K].X-Old+Base;
   If Code[K].Y>=0 Then RxP[I].Y:=Code[K].Y-Old+Base;
  End;
 End;
End;

{ une sequence d'atomes avec quantificateurs jusqu'a | ou ) }
Procedure RxSeq;
Var
 Start,I,Mn,Mx,K,J,Ln,Sp,P2:LongInt;
 Q:Char;
 Lazy:Boolean;
 Code:Array of TRxIns;
Begin
 While(RxPos<=Length(RxSrc))and(RxSrc[RxPos]<>'|')and(RxSrc[RxPos]<>')')do Begin
  Start:=RxN;
  RxAtom;
  If RxErr Then Exit;
  If RxPos>Length(RxSrc)Then Break;
  Q:=RxSrc[RxPos];
  Mn:=-1;Mx:=-1;
  If Q='*' Then Begin Mn:=0;Mx:=-2;Inc(RxPos);End
  Else If Q='+' Then Begin Mn:=1;Mx:=-2;Inc(RxPos);End
  Else If Q='?' Then Begin Mn:=0;Mx:=1;Inc(RxPos);End
  Else If Q='{' Then Begin
   P2:=Pos('}',Copy(RxSrc,RxPos,Length(RxSrc)));
   If P2>0 Then Begin
    Sp:=Pos(',',Copy(RxSrc,RxPos,P2));
    If Sp=0 Then Begin
     Mn:=ToInt(Copy(RxSrc,RxPos+1,P2-2),-1);Mx:=Mn;
    End
    Else Begin
     Mn:=ToInt(Copy(RxSrc,RxPos+1,Sp-2),0);
     If P2-Sp=1 Then Mx:=-2 Else Mx:=ToInt(Copy(RxSrc,RxPos+Sp,P2-Sp-1),-2);
    End;
    If Mn>=0 Then Inc(RxPos,P2);
   End;
  End;
  If Mn<0 Then Continue;
  Lazy:=False;
  If(RxPos<=Length(RxSrc))and(RxSrc[RxPos]='?')Then Begin Lazy:=True;Inc(RxPos);End;
  Ln:=RxN-Start;
  SetLength(Code,Ln);
  For K:=0 to Ln-1 do Code[K]:=RxP[Start+K];
  RxN:=Start;
  For J:=1 to Mn do RxCopy(Code,Ln,Start);
  If Mx=-2 Then Begin
   I:=RxEmit(RX_SPLIT);
   RxCopy(Code,Ln,Start);
   J:=RxEmit(RX_JMP);RxP[J].X:=I;
   If Lazy Then Begin RxP[I].X:=RxN;RxP[I].Y:=I+1;End
   Else Begin RxP[I].X:=I+1;RxP[I].Y:=RxN;End;
  End
  Else If Mx>Mn Then Begin
   Sp:=RxN;
   For J:=1 to Mx-Mn do Begin
    I:=RxEmit(RX_SPLIT);
    RxP[I].X:=I+1;RxP[I].Y:=-1;
    RxCopy(Code,Ln,Start);
   End;
   For K:=Sp to RxN-1 do If(RxP[K].Op=RX_SPLIT)and(RxP[K].Y=-1)Then Begin
    RxP[K].Y:=RxN;
    If Lazy Then Begin J:=RxP[K].X;RxP[K].X:=RxP[K].Y;RxP[K].Y:=J;End;
   End;
  End;
 End;
End;

Procedure RxAlt;
Var
 Sp,Jm,Here:LongInt;
 Jumps:Array[0..31]of LongInt;
 NJ,K,Start,Ln:LongInt;
 Code:Array of TRxIns;
Begin
 Start:=RxN;
 NJ:=0;
 RxSeq;
 While(not RxErr)and(RxPos<=Length(RxSrc))and(RxSrc[RxPos]='|')do Begin
  Inc(RxPos);
  Ln:=RxN-Start;
  SetLength(Code,Ln);
  For K:=0 to Ln-1 do Code[K]:=RxP[Start+K];
  RxN:=Start;
  Sp:=RxEmit(RX_SPLIT);
  RxCopy(Code,Ln,Start);
  For K:=0 to NJ-1 do Inc(Jumps[K]);
  Jm:=RxEmit(RX_JMP);
  If NJ<32 Then Begin Jumps[NJ]:=Jm;Inc(NJ);End;
  RxP[Sp].X:=Sp+1;RxP[Sp].Y:=RxN;
  RxSeq;
 End;
 Here:=RxN;
 For K:=0 to NJ-1 do RxP[Jumps[K]].X:=Here;
End;

Function RxWordCh(C:Char):Boolean;
Begin
 RxWordCh:=C in['a'..'z','A'..'Z','0'..'9','_'];
End;

Function RxRun(Pc,Sp:LongInt):Boolean;
Var
 Old:LongInt;
 C:Char;
Begin
 RxRun:=False;
 While True do Begin
  Inc(RxSteps);
  If RxSteps>2000000 Then Exit;
  Case RxP[Pc].Op of
   RX_CHAR:Begin
            If Sp>Length(RxStr)Then Exit;
            C:=RxStr[Sp];
            If RxIcase Then Begin
             If UpCase(C)<>UpCase(RxP[Pc].C)Then Exit;
            End
            Else If C<>RxP[Pc].C Then Exit;
            Inc(Sp);Inc(Pc);
           End;
   RX_ANY:Begin
           If Sp>Length(RxStr)Then Exit;
           Inc(Sp);
           While(Sp<=Length(RxStr))and((Ord(RxStr[Sp])and $C0)=$80)do Inc(Sp);
           Inc(Pc);
          End;
   RX_CLASS:Begin
             If Sp>Length(RxStr)Then Exit;
             If(RxStr[Sp]in RxP[Pc].Set_)=RxP[Pc].Neg Then Exit;
             Inc(Sp);
             While(Sp<=Length(RxStr))and((Ord(RxStr[Sp])and $C0)=$80)do Inc(Sp);
             Inc(Pc);
            End;
   RX_BOL:Begin If Sp<>1 Then Exit;Inc(Pc);End;
   RX_EOL:Begin If Sp<>Length(RxStr)+1 Then Exit;Inc(Pc);End;
   RX_WORDB,RX_NWORDB:Begin
     C:=#0;
     Old:=0;
     If(Sp>1)and RxWordCh(RxStr[Sp-1])Then Old:=Old+1;
     If(Sp<=Length(RxStr))and RxWordCh(RxStr[Sp])Then Old:=Old+1;
     If(RxP[Pc].Op=RX_WORDB)=(Old<>1)Then Exit;
     Inc(Pc);
    End;
   RX_JMP:Pc:=RxP[Pc].X;
   RX_SPLIT:Begin
             If RxRun(RxP[Pc].X,Sp)Then Begin RxRun:=True;Exit;End;
             Pc:=RxP[Pc].Y;
            End;
   RX_SAVE:Begin
            Old:=RxCap[RxP[Pc].X];
            RxCap[RxP[Pc].X]:=Sp;
            If RxRun(Pc+1,Sp)Then Begin RxRun:=True;Exit;End;
            RxCap[RxP[Pc].X]:=Old;
            Exit;
           End;
   RX_MATCH:Begin RxCap[1]:=Sp;RxRun:=True;Exit;End;
   Else Exit;
  End;
 End;
End;

{ compile ; renvoie False si l'expression est invalide }
Function RxCompile(Const Pat:AnsiString;Icase,Ext:Boolean):Boolean;
Var
 I:LongInt;
 T:AnsiString;
Begin
 T:=Pat;
 If Ext Then Begin
  T:=ReplaceAll(ReplaceAll(ReplaceAll(T,' ',''),#10,''),#9,'');
 End;
 RxSrc:=T;RxPos:=1;RxN:=0;RxErr:=False;RxNGroups:=0;RxIcase:=Icase;
 SetLength(RxP,0);
 For I:=0 to 9 do RxGroupNames[I]:='';
 RxAlt;
 If RxPos<=Length(RxSrc)Then RxErr:=True;
 RxEmit(RX_MATCH);
 RxCompile:=not RxErr;
End;

{ recherche a partir de From (1-base) ; RxCap[0..1] = debut et fin (exclue) }
Function RxSearch(Const S:AnsiString;From:LongInt):Boolean;
Var
 St,I:LongInt;
Begin
 RxStr:=S;
 For St:=From to Length(S)+1 do Begin
  If(St>1)and(St<=Length(S))and((Ord(S[St])and $C0)=$80)Then Continue;
  For I:=0 to 19 do RxCap[I]:=0;
  RxCap[0]:=St;
  RxSteps:=0;
  If RxRun(0,St)Then Begin RxSearch:=True;Exit;End;
 End;
 RxSearch:=False;
End;
{ ------------------------------------------------------------------ }
{ jq : valeurs, analyse syntaxique                                    }
{ ------------------------------------------------------------------ }

Const
 Q_ID=1; Q_REC=2; Q_FIELD=3; Q_INDEX=4; Q_SLICE=5; Q_ITER=6; Q_LIT=7; Q_NUM=8; Q_BOOL=9; Q_NULL=10;
 Q_ARR=11; Q_OBJ=12; Q_ENT=13; Q_NEG=14; Q_PIPE=15; Q_COMMA=16; Q_BIN=17; Q_AND=18; Q_OR=19;
 Q_ALT=20; Q_IF=21; Q_FUNC=22; Q_VAR=23; Q_AS=24; Q_REDUCE=25; Q_TRY=26; Q_FMT=27; Q_STR=28;
 Q_FOREACH=29; Q_ASSIGN=30;

Type
 TJq = Record
  Kd:Byte;
  S:AnsiString;
  D:Double;
  A,B,C,Nx:LongInt;
 End;

Var
 JqT:Array of TJq;
 JqNN:LongInt;
 JqSrc:AnsiString;
 JqPos:LongInt;
 JqErrS:AnsiString;
 TkK:Char;
 TkS:AnsiString;
 TkD:Double;
 TkNode:LongInt;

Function QNew(Kd:Byte;Const S:AnsiString;A,B,C:LongInt):LongInt;
Begin
 If JqNN>=Length(JqT)Then SetLength(JqT,Length(JqT)*2+64);
 JqT[JqNN].Kd:=Kd;JqT[JqNN].S:=S;JqT[JqNN].D:=0;
 JqT[JqNN].A:=A;JqT[JqNN].B:=B;JqT[JqNN].C:=C;JqT[JqNN].Nx:=-1;
 QNew:=JqNN;
 Inc(JqNN);
End;

Procedure JqFail(Const M:AnsiString);
Begin
 If JqErrS='' Then JqErrS:=M;
End;

{ ---------- valeurs ---------- }

Function NumStr(D:Double):AnsiString;
Var
 S:AnsiString;
 I:LongInt;
Begin
 If(Frac(D)=0)and(Abs(D)<1E15)Then Begin Str(Trunc(D),S);NumStr:=S;Exit;End;
 Str(D:0:12,S);
 If Pos('.',S)>0 Then Begin
  I:=Length(S);
  While(I>0)and(S[I]='0')do Dec(I);
  If S[I]='.' Then Dec(I);
  S:=Copy(S,1,I);
 End;
 NumStr:=S;
End;

Function MkStr(Const S:AnsiString):LongInt;
Var
 K:LongInt;
Begin
 K:=JNew(JK_STR);JP[K].S:=S;MkStr:=K;
End;

Function MkNum(D:Double):LongInt;
Var
 K:LongInt;
Begin
 K:=JNew(JK_NUM);JP[K].S:=NumStr(D);MkNum:=K;
End;

Function MkBool(B:Boolean):LongInt;
Var
 K:LongInt;
Begin
 K:=JNew(JK_BOOL);
 If B Then JP[K].S:='true' Else JP[K].S:='false';
 MkBool:=K;
End;

Function MkNull:LongInt;
Begin
 MkNull:=JNew(JK_NULL);
End;

Function MkArr:LongInt;
Begin
 MkArr:=JNew(JK_ARR);
End;

Function MkObj:LongInt;
Begin
 MkObj:=JNew(JK_OBJ);
End;

Function Cpy(N:LongInt):LongInt;
Var
 C,K,X:LongInt;
Begin
 If N<0 Then Begin Cpy:=MkNull;Exit;End;
 K:=JNew(JP[N].Kind);
 JP[K].S:=JP[N].S;
 If JP[N].Kind in[JK_ARR,JK_OBJ]Then Begin
  C:=JP[N].First;
  While C>=0 do Begin
   X:=Cpy(C);
   JP[X].Key:=JP[C].Key;
   JAppend(K,X);
   C:=JP[C].Next;
  End;
 End;
 Cpy:=K;
End;

{ ---------- analyse lexicale ---------- }

Function JqIdentCh(C:Char):Boolean;
Begin
 JqIdentCh:=C in['a'..'z','A'..'Z','0'..'9','_'];
End;

Function PPipe:LongInt;forward;
Procedure NextTok;forward;

{ lit une chaine "..." (JqPos sur le guillemet ouvrant) ; renvoie le noeud }
Function LexString:LongInt;
Var
 B:TBuf;
 First,Last,Part,E:LongInt;
 C:Char;
 U,U2:LongInt;
 HasExpr:Boolean;
 Procedure AddPart(P:LongInt);
 Begin
  If First<0 Then First:=P Else JqT[Last].Nx:=P;
  Last:=P;
 End;
 Procedure FlushLit;
 Begin
  Part:=QNew(Q_LIT,BufStr(B),-1,-1,-1);
  AddPart(Part);
  BufClear(B);
 End;
Begin
 BufClear(B);
 First:=-1;Last:=-1;HasExpr:=False;
 Inc(JqPos);
 While True do Begin
  If JqPos>Length(JqSrc)Then Begin JqFail('unterminated string literal');Break;End;
  C:=JqSrc[JqPos];
  If C='"' Then Begin Inc(JqPos);Break;End;
  If C='\' Then Begin
   Inc(JqPos);
   If JqPos>Length(JqSrc)Then Break;
   C:=JqSrc[JqPos];
   Case C of
    'n':BufAdd(B,#10);
    't':BufAdd(B,#9);
    'r':BufAdd(B,#13);
    'b':BufAdd(B,#8);
    'f':BufAdd(B,#12);
    'u':Begin
         JErr:=False;
         U:=HexVal(JqSrc,JqPos+1);
         Inc(JqPos,4);
         If(U>=$D800)and(U<$DC00)and(Copy(JqSrc,JqPos+1,2)='\u')Then Begin
          U2:=HexVal(JqSrc,JqPos+3);
          If(U2>=$DC00)and(U2<$E000)Then Begin
           U:=$10000+((U-$D800)shl 10)+(U2-$DC00);
           Inc(JqPos,6);
          End;
         End;
         BufAdd(B,Utf8Enc(U));
        End;
    '(':Begin
         If B.N>0 Then FlushLit;
         HasExpr:=True;
         Inc(JqPos);
         NextTok;
         E:=PPipe;
         If(TkK<>'o')or(TkS<>')')Then JqFail('syntax error in string interpolation');
         Part:=QNew(Q_FMT,'',E,-1,-1);
         AddPart(Part);
         Continue;
        End;
    Else BufAdd(B,C);
   End;
   Inc(JqPos);
  End
  Else Begin BufAdd(B,C);Inc(JqPos);End;
 End;
 If not HasExpr Then Begin
  LexString:=QNew(Q_LIT,BufStr(B),-1,-1,-1);
  Exit;
 End;
 If B.N>0 Then FlushLit;
 LexString:=QNew(Q_STR,'',First,-1,-1);
End;

Procedure NextTok;
Const
 Ops:Array[0..13]of AnsiString=('?//','//=','|=','+=','-=','*=','/=','%=','==','!=','<=','>=','//',
   '..');
Var
 C,D:Char;
 S:AnsiString;
 I,St:LongInt;
 Code:LongInt;
Begin
 TkS:='';TkNode:=-1;
 While JqPos<=Length(JqSrc)do Begin
  C:=JqSrc[JqPos];
  If C in[' ',#9,#10,#13]Then Inc(JqPos)
  Else If C='#' Then Begin
   While(JqPos<=Length(JqSrc))and(JqSrc[JqPos]<>#10)do Inc(JqPos);
  End
  Else Break;
 End;
 If JqPos>Length(JqSrc)Then Begin TkK:='e';Exit;End;
 C:=JqSrc[JqPos];
 If JqPos<Length(JqSrc)Then D:=JqSrc[JqPos+1] Else D:=#0;
 If C='.' Then Begin
  If D='.' Then Begin TkK:='R';Inc(JqPos,2);Exit;End;
  If(D in['a'..'z','A'..'Z','_'])Then Begin
   Inc(JqPos);St:=JqPos;
   While(JqPos<=Length(JqSrc))and JqIdentCh(JqSrc[JqPos])do Inc(JqPos);
   TkK:='f';TkS:=Copy(JqSrc,St,JqPos-St);
   Exit;
  End;
  If D='"' Then Begin
   Inc(JqPos);
   TkNode:=LexString;TkK:='F';
   Exit;
  End;
  If D in['0'..'9']Then Begin
   St:=JqPos;Inc(JqPos);
   While(JqPos<=Length(JqSrc))and(JqSrc[JqPos]in['0'..'9','e','E'])do Inc(JqPos);
   Val('0'+Copy(JqSrc,St,JqPos-St),TkD,Code);
   TkK:='n';TkS:='';Exit;
  End;
  TkK:='.';Inc(JqPos);Exit;
 End;
 If C='"' Then Begin
  TkNode:=LexString;TkK:='s';Exit;
 End;
 If C in['0'..'9']Then Begin
  St:=JqPos;
  While(JqPos<=Length(JqSrc))and(JqSrc[JqPos]in['0'..'9'])do Inc(JqPos);
  If(JqPos<=Length(JqSrc))and(JqSrc[JqPos]='.')Then Begin
   Inc(JqPos);
   While(JqPos<=Length(JqSrc))and(JqSrc[JqPos]in['0'..'9'])do Inc(JqPos);
  End;
  If(JqPos<=Length(JqSrc))and(JqSrc[JqPos]in['e','E'])Then Begin
   Inc(JqPos);
   If(JqPos<=Length(JqSrc))and(JqSrc[JqPos]in['+','-'])Then Inc(JqPos);
   While(JqPos<=Length(JqSrc))and(JqSrc[JqPos]in['0'..'9'])do Inc(JqPos);
  End;
  Val(Copy(JqSrc,St,JqPos-St),TkD,Code);
  TkK:='n';TkS:=Copy(JqSrc,St,JqPos-St);Exit;
 End;
 If C='$' Then Begin
  Inc(JqPos);St:=JqPos;
  While(JqPos<=Length(JqSrc))and JqIdentCh(JqSrc[JqPos])do Inc(JqPos);
  TkK:='v';TkS:=Copy(JqSrc,St,JqPos-St);Exit;
 End;
 If C='@' Then Begin
  Inc(JqPos);St:=JqPos;
  While(JqPos<=Length(JqSrc))and JqIdentCh(JqSrc[JqPos])do Inc(JqPos);
  TkK:='@';TkS:=Copy(JqSrc,St,JqPos-St);Exit;
 End;
 If C in['a'..'z','A'..'Z','_']Then Begin
  St:=JqPos;
  While(JqPos<=Length(JqSrc))and JqIdentCh(JqSrc[JqPos])do Inc(JqPos);
  TkK:='i';TkS:=Copy(JqSrc,St,JqPos-St);Exit;
 End;
 For I:=0 to 13 do Begin
  S:=Ops[I];
  If Copy(JqSrc,JqPos,Length(S))=S Then Begin
   TkK:='o';TkS:=S;Inc(JqPos,Length(S));Exit;
  End;
 End;
 TkK:='o';TkS:=C;Inc(JqPos);
End;

Function IsOp(Const S:AnsiString):Boolean;
Begin
 IsOp:=(TkK='o')and(TkS=S);
End;

Function IsKw(Const S:AnsiString):Boolean;
Begin
 IsKw:=(TkK='i')and(TkS=S);
End;

Procedure ExpectOp(Const S:AnsiString);
Begin
 If IsOp(S)Then NextTok Else JqFail('syntax error: expected '''+S+'''');
End;

Procedure ExpectKw(Const S:AnsiString);
Begin
 If IsKw(S)Then NextTok Else JqFail('syntax error: expected '''+S+'''');
End;

Function PAlt:LongInt;forward;
Function POr:LongInt;forward;
Function PPostfix(AllowAs:Boolean):LongInt;forward;

Function PObject:LongInt;
Var
 First,Last,Ent,K,V:LongInt;
 Nm:AnsiString;
Begin
 First:=-1;Last:=-1;
 NextTok;
 While(JqErrS='')and not IsOp('}')do Begin
  K:=-1;V:=-1;
  If(TkK='i')or(TkK='n')Then Begin
   Nm:=TkS;
   If TkK='n' Then Nm:=NumStr(TkD);
   K:=QNew(Q_LIT,Nm,-1,-1,-1);
   NextTok;
   If not IsOp(':')Then V:=QNew(Q_FIELD,Nm,QNew(Q_ID,'',-1,-1,-1),-1,-1);
  End
  Else If TkK='s' Then Begin
   K:=TkNode;
   NextTok;
   If not IsOp(':')Then Begin
    If JqT[K].Kd=Q_LIT Then V:=QNew(Q_FIELD,JqT[K].S,QNew(Q_ID,'',-1,-1,-1),-1,-1)
    Else JqFail('syntax error: object key');
   End;
  End
  Else If TkK='v' Then Begin
   K:=QNew(Q_LIT,TkS,-1,-1,-1);
   V:=QNew(Q_VAR,TkS,-1,-1,-1);
   NextTok;
  End
  Else If IsOp('(')Then Begin
   NextTok;
   K:=PPipe;
   ExpectOp(')');
  End
  Else Begin JqFail('syntax error in object construction');Break;End;
  If IsOp(':')Then Begin
   NextTok;
   V:=PAlt;
   While IsOp('|')do Begin
    NextTok;
    V:=QNew(Q_PIPE,'',V,PAlt,-1);
   End;
  End;
  Ent:=QNew(Q_ENT,'',K,V,-1);
  If First<0 Then First:=Ent Else JqT[Last].Nx:=Ent;
  Last:=Ent;
  If IsOp(',')Then NextTok Else Break;
 End;
 ExpectOp('}');
 PObject:=QNew(Q_OBJ,'',First,-1,-1);
End;

Function PIf:LongInt;
Var
 A,B,C:LongInt;
Begin
 NextTok;
 A:=PPipe;
 ExpectKw('then');
 B:=PPipe;
 If IsKw('elif')Then C:=PIf()
 Else If IsKw('else')Then Begin
  NextTok;
  C:=PPipe;
  ExpectKw('end');
 End
 Else Begin
  C:=QNew(Q_ID,'',-1,-1,-1);
  ExpectKw('end');
 End;
 PIf:=QNew(Q_IF,'',A,B,C);
End;

Function PPrimary:LongInt;
Var
 Nm:AnsiString;
 A,B,C,N,I:LongInt;
 Args:Array[0..3]of LongInt;
 T:LongInt;
Begin
 PPrimary:=QNew(Q_NULL,'',-1,-1,-1);
 If JqErrS<>'' Then Exit;
 Case TkK of
  'n':Begin
       PPrimary:=QNew(Q_NUM,TkS,-1,-1,-1);JqT[PPrimary].D:=TkD;
       If TkS='' Then JqT[PPrimary].S:=NumStr(TkD);
       NextTok;
      End;
  's':Begin PPrimary:=TkNode;NextTok;End;
  'f':Begin PPrimary:=QNew(Q_FIELD,TkS,QNew(Q_ID,'',-1,-1,-1),-1,-1);NextTok;End;
  'F':Begin PPrimary:=QNew(Q_INDEX,'',QNew(Q_ID,'',-1,-1,-1),TkNode,-1);NextTok;End;
  '.':Begin PPrimary:=QNew(Q_ID,'',-1,-1,-1);NextTok;End;
  'R':Begin PPrimary:=QNew(Q_REC,'',-1,-1,-1);NextTok;End;
  'v':Begin
       If TkS='__loc__' Then PPrimary:=QNew(Q_LIT,'<top-level>',-1,-1,-1)
       Else PPrimary:=QNew(Q_VAR,TkS,-1,-1,-1);
       NextTok;
      End;
  '@':Begin
       Nm:=TkS;
       NextTok;
       If TkK='s' Then Begin
        A:=TkNode;
        If JqT[A].Kd=Q_STR Then Begin
         JqT[A].S:=Nm;
         T:=JqT[A].A;
         While T>=0 do Begin If JqT[T].Kd=Q_FMT Then JqT[T].S:=Nm;T:=JqT[T].Nx;End;
        End;
        PPrimary:=A;
        NextTok;
       End
       Else PPrimary:=QNew(Q_FMT,Nm,-1,-1,-1);
      End;
  'o':Begin
       If TkS='(' Then Begin
        NextTok;
        PPrimary:=PPipe;
        ExpectOp(')');
       End
       Else If TkS='[' Then Begin
        NextTok;
        If IsOp(']')Then Begin NextTok;PPrimary:=QNew(Q_ARR,'',-1,-1,-1);End
        Else Begin
         A:=PPipe;
         ExpectOp(']');
         PPrimary:=QNew(Q_ARR,'',A,-1,-1);
        End;
       End
       Else If TkS='{' Then PPrimary:=PObject
       Else If TkS='-' Then Begin
        NextTok;
        PPrimary:=QNew(Q_NEG,'',PPostfix(True),-1,-1);
       End
       Else JqFail('syntax error: unexpected '''+TkS+'''');
      End;
  'i':Begin
       Nm:=TkS;
       If Nm='true' Then Begin PPrimary:=QNew(Q_BOOL,'true',-1,-1,-1);NextTok;End
       Else If Nm='false' Then Begin PPrimary:=QNew(Q_BOOL,'false',-1,-1,-1);NextTok;End
       Else If Nm='null' Then Begin PPrimary:=QNew(Q_NULL,'',-1,-1,-1);NextTok;End
       Else If Nm='if' Then PPrimary:=PIf
       Else If Nm='try' Then Begin
        NextTok;
        A:=PPostfix(False);
        B:=-1;
        If IsKw('catch')Then Begin NextTok;B:=PPostfix(False);End;
        PPrimary:=QNew(Q_TRY,'',A,B,-1);
       End
       Else If Nm='reduce' Then Begin
        NextTok;
        A:=PPostfix(False);
        ExpectKw('as');
        Nm:='';
        If TkK<>'v' Then JqFail('syntax error: expected variable') Else Begin
         Nm:=TkS;NextTok;
        End;
        ExpectOp('(');
        B:=PPipe;
        ExpectOp(';');
        C:=PPipe;
        ExpectOp(')');
        PPrimary:=QNew(Q_REDUCE,Nm,A,B,C);
       End
       Else If Nm='foreach' Then Begin
        NextTok;
        A:=PPostfix(False);
        ExpectKw('as');
        Nm:='';
        If TkK<>'v' Then JqFail('syntax error: expected variable') Else Begin
         Nm:=TkS;NextTok;
        End;
        ExpectOp('(');
        B:=PPipe;
        ExpectOp(';');
        C:=PPipe;
        N:=-1;
        If IsOp(';')Then Begin NextTok;N:=PPipe;End;
        ExpectOp(')');
        PPrimary:=QNew(Q_FOREACH,Nm,A,B,C);
        JqT[PPrimary].Nx:=N;
       End
       Else If Nm='def' Then JqFail('function definitions are not supported')
       Else Begin
        NextTok;
        N:=0;
        For I:=0 to 3 do Args[I]:=-1;
        If IsOp('(')Then Begin
         NextTok;
         While JqErrS='' do Begin
          If N<4 Then Args[N]:=PPipe Else PPipe;
          Inc(N);
          If IsOp(';')Then NextTok Else Break;
         End;
         ExpectOp(')');
        End;
        PPrimary:=QNew(Q_FUNC,Nm,Args[0],Args[1],Args[2]);
        JqT[PPrimary].D:=N;
       End;
      End;
  Else JqFail('syntax error: unexpected end of expression');
 End;
End;

Function PPostfix(AllowAs:Boolean):LongInt;
Var
 T,A,B:LongInt;
 Nm:AnsiString;
Begin
 T:=PPrimary;
 While JqErrS='' do Begin
  If TkK='f' Then Begin T:=QNew(Q_FIELD,TkS,T,-1,-1);NextTok;End
  Else If TkK='F' Then Begin T:=QNew(Q_INDEX,'',T,TkNode,-1);NextTok;End
  Else If TkK='.' Then Begin
   NextTok;
   If not IsOp('[')Then Begin JqFail('syntax error: unexpected ''.''');Break;End;
  End
  Else If IsOp('[')Then Begin
   NextTok;
   If IsOp(']')Then Begin NextTok;T:=QNew(Q_ITER,'',T,-1,-1);End
   Else If IsOp(':')Then Begin
    NextTok;
    B:=PPipe;
    ExpectOp(']');
    T:=QNew(Q_SLICE,'',T,-1,B);
   End
   Else Begin
    A:=PPipe;
    If IsOp(':')Then Begin
     NextTok;
     If IsOp(']')Then B:=-1 Else B:=PPipe;
     ExpectOp(']');
     T:=QNew(Q_SLICE,'',T,A,B);
    End
    Else Begin
     ExpectOp(']');
     T:=QNew(Q_INDEX,'',T,A,-1);
    End;
   End;
  End
  Else If IsOp('?')Then Begin
   NextTok;
   T:=QNew(Q_TRY,'',T,-1,-1);
  End
  Else If AllowAs and IsKw('as')Then Begin
   NextTok;
   If TkK<>'v' Then Begin JqFail('syntax error: expected variable after ''as''');Break;End;
   Nm:=TkS;NextTok;
   ExpectOp('|');
   B:=PPipe;
   T:=QNew(Q_AS,Nm,T,B,-1);
   Break;
  End
  Else Break;
 End;
 PPostfix:=T;
End;

Function PUnary:LongInt;
Begin
 If IsOp('-')Then Begin
  NextTok;
  PUnary:=QNew(Q_NEG,'',PUnary(),-1,-1);
 End
 Else PUnary:=PPostfix(True);
End;

Function PMul:LongInt;
Var
 L,R:LongInt;
 Op:AnsiString;
Begin
 L:=PUnary;
 While(JqErrS='')and(IsOp('*')or IsOp('/')or IsOp('%'))do Begin
  Op:=TkS;NextTok;
  R:=PUnary;
  L:=QNew(Q_BIN,Op,L,R,-1);
 End;
 PMul:=L;
End;

Function PAdd:LongInt;
Var
 L,R:LongInt;
 Op:AnsiString;
Begin
 L:=PMul;
 While(JqErrS='')and(IsOp('+')or IsOp('-'))do Begin
  Op:=TkS;NextTok;
  R:=PMul;
  L:=QNew(Q_BIN,Op,L,R,-1);
 End;
 PAdd:=L;
End;

Function PCmp:LongInt;
Var
 L,R:LongInt;
 Op:AnsiString;
Begin
 L:=PAdd;
 If(JqErrS='')and(IsOp('==')or IsOp('!=')or IsOp('<')or IsOp('<=')or IsOp('>')or IsOp('>='))Then Begin
  Op:=TkS;NextTok;
  R:=PAdd;
  L:=QNew(Q_BIN,Op,L,R,-1);
 End;
 PCmp:=L;
End;

Function PAnd:LongInt;
Var
 L:LongInt;
Begin
 L:=PCmp;
 While(JqErrS='')and IsKw('and')do Begin
  NextTok;
  L:=QNew(Q_AND,'',L,PCmp,-1);
 End;
 PAnd:=L;
End;

Function POr:LongInt;
Var
 L:LongInt;
Begin
 L:=PAnd;
 While(JqErrS='')and IsKw('or')do Begin
  NextTok;
  L:=QNew(Q_OR,'',L,PAnd,-1);
 End;
 POr:=L;
End;

Function PAssign:LongInt;
Var
 L,R:LongInt;
 Op:AnsiString;
Begin
 L:=POr;
 If(JqErrS='')and(TkK='o')and((TkS='=')or(TkS='|=')or(TkS='+=')or(TkS='-=')or(TkS='*=')or(TkS='/=')
   or(TkS='%=')or(TkS='//='))Then Begin
  Op:=TkS;NextTok;
  R:=PAlt();
  L:=QNew(Q_ASSIGN,Op,L,R,-1);
 End;
 PAssign:=L;
End;

Function PAlt:LongInt;
Var
 L:LongInt;
Begin
 L:=PAssign;
 If(JqErrS='')and IsOp('//')Then Begin
  NextTok;
  L:=QNew(Q_ALT,'',L,PAlt(),-1);
 End;
 PAlt:=L;
End;

Function PComma:LongInt;
Var
 L:LongInt;
Begin
 L:=PAlt;
 While(JqErrS='')and IsOp(',')do Begin
  NextTok;
  L:=QNew(Q_COMMA,'',L,PAlt,-1);
 End;
 PComma:=L;
End;

Function PPipe:LongInt;
Var
 L:LongInt;
Begin
 L:=PComma;
 If(JqErrS='')and IsOp('|')Then Begin
  NextTok;
  L:=QNew(Q_PIPE,'',L,PPipe(),-1);
 End;
 PPipe:=L;
End;

{ analyse un programme jq ; renvoie la racine ou -1 }
Function JqCompile(Const Prog:AnsiString):LongInt;
Begin
 JqSrc:=Prog;JqPos:=1;JqErrS:='';
 JqNN:=0;SetLength(JqT,0);
 NextTok;
 If TkK='e' Then JqCompile:=QNew(Q_ID,'',-1,-1,-1)
 Else Begin
  JqCompile:=PPipe;
  If(JqErrS='')and(TkK<>'e')Then JqFail('syntax error: unexpected '''+IfThen_(TkS<>'',TkS,TkK)+'''');
 End;
 If JqErrS<>'' Then JqCompile:=-1;
End;
{ ------------------------------------------------------------------ }
{ jq : evaluation                                                     }
{ ------------------------------------------------------------------ }

Var
 VarN:LongInt;
 VarName:Array[0..127]of AnsiString;
 VarVal:Array[0..127]of LongInt;
 EnvNodeCache:LongInt;

Procedure Ev(P,In_:LongInt;Var Out:TIList);forward;

Function TypeName(N:LongInt):AnsiString;
Begin
 If N<0 Then Begin TypeName:='null';Exit;End;
 Case JP[N].Kind of
  JK_NULL:TypeName:='null';
  JK_BOOL:TypeName:='boolean';
  JK_NUM:TypeName:='number';
  JK_STR:TypeName:='string';
  JK_ARR:TypeName:='array';
  Else TypeName:='object';
 End;
End;

Function TypeOrd(N:LongInt):LongInt;
Begin
 TypeOrd:=0;
 If N<0 Then Exit;
 Case JP[N].Kind of
  JK_NULL:TypeOrd:=0;
  JK_BOOL:If JP[N].S='true' Then TypeOrd:=2 Else TypeOrd:=1;
  JK_NUM:TypeOrd:=3;
  JK_STR:TypeOrd:=4;
  JK_ARR:TypeOrd:=5;
  Else TypeOrd:=6;
 End;
End;

Function Truthy(N:LongInt):Boolean;
Begin
 Truthy:=TypeOrd(N)>=2;
End;

Function NumOf(N:LongInt):Double;
Var
 D:Double;
 C:LongInt;
Begin
 NumOf:=0;
 If(N>=0)and(JP[N].Kind=JK_NUM)Then Begin
  Val(JP[N].S,D,C);
  If C=0 Then NumOf:=D;
 End;
End;

Function ToStr(N:LongInt):AnsiString;
Begin
 If N<0 Then ToStr:='null'
 Else If JP[N].Kind=JK_STR Then ToStr:=JP[N].S
 Else ToStr:=RawJson(N);
End;

Function U8Len(Const S:AnsiString):LongInt;
Begin
 U8Len:=DispLen(S);
End;

{ sous-chaine en points de code (indices 0-base, [A,B[) }
Function U8Sub(Const S:AnsiString;A,B:LongInt):AnsiString;
Var
 I,C,St,En:LongInt;
Begin
 St:=Length(S)+1;En:=Length(S)+1;C:=0;
 For I:=1 to Length(S)do If(Ord(S[I])and $C0)<>$80 Then Begin
  If C=A Then St:=I;
  If C=B Then Begin En:=I;Break;End;
  Inc(C);
 End;
 If A>=C Then St:=Length(S)+1;
 U8Sub:=Copy(S,St,En-St);
End;

Function JCmp(A,B:LongInt):LongInt;
Var
 TA,TB,CA,CB,R:LongInt;
 DA,DB:Double;
 KA,KB:TSList;
 I:LongInt;
Begin
 TA:=TypeOrd(A);TB:=TypeOrd(B);
 If TA<>TB Then Begin
  If TA<TB Then JCmp:=-1 Else JCmp:=1;
  Exit;
 End;
 JCmp:=0;
 Case TA of
  3:Begin
     DA:=NumOf(A);DB:=NumOf(B);
     If DA<DB Then JCmp:=-1 Else If DA>DB Then JCmp:=1;
    End;
  4:Begin
     If JP[A].S<JP[B].S Then JCmp:=-1 Else If JP[A].S>JP[B].S Then JCmp:=1;
    End;
  5:Begin
     CA:=JP[A].First;CB:=JP[B].First;
     While(CA>=0)and(CB>=0)do Begin
      R:=JCmp(CA,CB);
      If R<>0 Then Begin JCmp:=R;Exit;End;
      CA:=JP[CA].Next;CB:=JP[CB].Next;
     End;
     If(CA<0)and(CB>=0)Then JCmp:=-1 Else If(CA>=0)and(CB<0)Then JCmp:=1;
    End;
  6:Begin
     SClear(KA);SClear(KB);
     CA:=JP[A].First;
     While CA>=0 do Begin SAdd(KA,JP[CA].Key);CA:=JP[CA].Next;End;
     CB:=JP[B].First;
     While CB>=0 do Begin SAdd(KB,JP[CB].Key);CB:=JP[CB].Next;End;
     SSort(KA);SSort(KB);
     For I:=0 to KA.N-1 do Begin
      If I>=KB.N Then Begin JCmp:=1;Exit;End;
      If KA.A[I]<KB.A[I]Then Begin JCmp:=-1;Exit;End;
      If KA.A[I]>KB.A[I]Then Begin JCmp:=1;Exit;End;
     End;
     If KB.N>KA.N Then Begin JCmp:=-1;Exit;End;
     For I:=0 to KA.N-1 do Begin
      R:=JCmp(JGet(A,KA.A[I]),JGet(B,KA.A[I]));
      If R<>0 Then Begin JCmp:=R;Exit;End;
     End;
    End;
 End;
End;

{ remplace ou ajoute une cle d'objet (copie de V) }
Procedure ObjSet(O:LongInt;Const Key:AnsiString;V:LongInt);
Var
 C,Prev,X:LongInt;
Begin
 X:=Cpy(V);
 JP[X].Key:=Key;
 Prev:=-1;
 C:=JP[O].First;
 While C>=0 do Begin
  If JP[C].Key=Key Then Begin
   JP[X].Next:=JP[C].Next;
   If Prev<0 Then JP[O].First:=X Else JP[Prev].Next:=X;
   If JP[O].Last=C Then JP[O].Last:=X;
   Exit;
  End;
  Prev:=C;C:=JP[C].Next;
 End;
 JAppend(O,X);
End;

Procedure ArrAdd(A,V:LongInt);
Var
 X:LongInt;
Begin
 X:=Cpy(V);
 JAppend(A,X);
End;

Function ObjMerge(A,B:LongInt;Deep:Boolean):LongInt;
Var
 R,C,E:LongInt;
Begin
 R:=Cpy(A);
 C:=JP[B].First;
 While C>=0 do Begin
  E:=JGet(R,JP[C].Key);
  If Deep and(E>=0)and(JP[E].Kind=JK_OBJ)and(JP[C].Kind=JK_OBJ)Then
    ObjSet(R,JP[C].Key,ObjMerge(E,C,True))
  Else ObjSet(R,JP[C].Key,C);
  C:=JP[C].Next;
 End;
 ObjMerge:=R;
End;

Function JEq(A,B:LongInt):Boolean;
Begin
 JEq:=JCmp(A,B)=0;
End;

Function BinOp(Const Op:AnsiString;A,B:LongInt):LongInt;
Var
 R,C,D:LongInt;
 X,Y:Double;
 L:TSList;
 S:AnsiString;
 I,N:LongInt;
 Found:Boolean;
Begin
 BinOp:=MkNull;
 If(Op='==')Then Begin BinOp:=MkBool(JCmp(A,B)=0);Exit;End;
 If(Op='!=')Then Begin BinOp:=MkBool(JCmp(A,B)<>0);Exit;End;
 If(Op='<')Then Begin BinOp:=MkBool(JCmp(A,B)<0);Exit;End;
 If(Op='<=')Then Begin BinOp:=MkBool(JCmp(A,B)<=0);Exit;End;
 If(Op='>')Then Begin BinOp:=MkBool(JCmp(A,B)>0);Exit;End;
 If(Op='>=')Then Begin BinOp:=MkBool(JCmp(A,B)>=0);Exit;End;
 If Op='+' Then Begin
  If TypeOrd(A)=0 Then Begin BinOp:=Cpy(B);Exit;End;
  If TypeOrd(B)=0 Then Begin BinOp:=Cpy(A);Exit;End;
  If(JP[A].Kind=JK_NUM)and(JP[B].Kind=JK_NUM)Then BinOp:=MkNum(NumOf(A)+NumOf(B))
  Else If(JP[A].Kind=JK_STR)and(JP[B].Kind=JK_STR)Then BinOp:=MkStr(JP[A].S+JP[B].S)
  Else If(JP[A].Kind=JK_ARR)and(JP[B].Kind=JK_ARR)Then Begin
   R:=Cpy(A);
   C:=JP[B].First;
   While C>=0 do Begin ArrAdd(R,C);C:=JP[C].Next;End;
   BinOp:=R;
  End
  Else If(JP[A].Kind=JK_OBJ)and(JP[B].Kind=JK_OBJ)Then BinOp:=ObjMerge(A,B,False)
  Else JqFail(TypeName(A)+' ('+Copy(ToStr(A),1,11)+') and '+TypeName(B)+' ('+Copy(ToStr(B),1,11)+
    ') cannot be added');
  Exit;
 End;
 If Op='-' Then Begin
  If(JP[A].Kind=JK_NUM)and(JP[B].Kind=JK_NUM)Then BinOp:=MkNum(NumOf(A)-NumOf(B))
  Else If(JP[A].Kind=JK_ARR)and(JP[B].Kind=JK_ARR)Then Begin
   R:=MkArr;
   C:=JP[A].First;
   While C>=0 do Begin
    Found:=False;
    D:=JP[B].First;
    While D>=0 do Begin If JEq(C,D)Then Found:=True;D:=JP[D].Next;End;
    If not Found Then ArrAdd(R,C);
    C:=JP[C].Next;
   End;
   BinOp:=R;
  End
  Else JqFail(TypeName(A)+' ('+Copy(ToStr(A),1,11)+') and '+TypeName(B)+' ('+Copy(ToStr(B),1,11)+
    ') cannot be subtracted');
  Exit;
 End;
 If Op='*' Then Begin
  If(JP[A].Kind=JK_NUM)and(JP[B].Kind=JK_NUM)Then BinOp:=MkNum(NumOf(A)*NumOf(B))
  Else If(JP[A].Kind=JK_STR)and(JP[B].Kind=JK_NUM)Then Begin
   N:=Trunc(NumOf(B));
   If N<=0 Then BinOp:=MkNull Else Begin
    S:='';
    For I:=1 to N do S:=S+JP[A].S;
    BinOp:=MkStr(S);
   End;
  End
  Else If(JP[A].Kind=JK_OBJ)and(JP[B].Kind=JK_OBJ)Then BinOp:=ObjMerge(A,B,True)
  Else JqFail(TypeName(A)+' ('+Copy(ToStr(A),1,11)+') and '+TypeName(B)+' ('+Copy(ToStr(B),1,11)+
    ') cannot be multiplied');
  Exit;
 End;
 If Op='/' Then Begin
  If(JP[A].Kind=JK_NUM)and(JP[B].Kind=JK_NUM)Then Begin
   If NumOf(B)=0 Then JqFail(TypeName(A)+' ('+ToStr(A)+') and '+TypeName(B)+' ('+ToStr(B)+
     ') cannot be divided because the divisor is zero')
   Else BinOp:=MkNum(NumOf(A)/NumOf(B));
  End
  Else If(JP[A].Kind=JK_STR)and(JP[B].Kind=JK_STR)Then Begin
   R:=MkArr;
   If JP[B].S='' Then Begin
    For I:=0 to U8Len(JP[A].S)-1 do ArrAdd(R,MkStr(U8Sub(JP[A].S,I,I+1)));
   End
   Else Begin
    S:=JP[A].S;
    While True do Begin
     N:=Pos(JP[B].S,S);
     If N=0 Then Break;
     ArrAdd(R,MkStr(Copy(S,1,N-1)));
     Delete(S,1,N+Length(JP[B].S)-1);
    End;
    ArrAdd(R,MkStr(S));
   End;
   BinOp:=R;
  End
  Else JqFail(TypeName(A)+' ('+Copy(ToStr(A),1,11)+') and '+TypeName(B)+' ('+Copy(ToStr(B),1,11)+
    ') cannot be divided');
  Exit;
 End;
 If Op='%' Then Begin
  If(JP[A].Kind=JK_NUM)and(JP[B].Kind=JK_NUM)Then Begin
   If Trunc(NumOf(B))=0 Then JqFail(TypeName(A)+' ('+ToStr(A)+') and '+TypeName(B)+' ('+ToStr(B)+
     ') cannot be divided because the divisor is zero')
   Else BinOp:=MkNum(Trunc(NumOf(A))mod Trunc(NumOf(B)));
  End
  Else JqFail(TypeName(A)+' ('+Copy(ToStr(A),1,11)+') and '+TypeName(B)+' ('+Copy(ToStr(B),1,11)+
    ') cannot be divided');
  Exit;
 End;
End;

{ ---------- formats @csv, @json ... ---------- }

Function FmtApply(Const F:AnsiString;N:LongInt):AnsiString;
Var
 C:LongInt;
 R,S:AnsiString;
 I:LongInt;
 B:TBuf;
 First:Boolean;
 Function CsvCell(X:LongInt):AnsiString;
 Begin
  Case JP[X].Kind of
   JK_NULL:CsvCell:='';
   JK_BOOL,JK_NUM:CsvCell:=JP[X].S;
   JK_STR:CsvCell:='"'+ReplaceAll(JP[X].S,'"','""')+'"';
   Else Begin JqFail(TypeName(X)+' ('+Copy(ToStr(X),1,11)+') is not valid in a csv row');CsvCell:='';End;
  End;
 End;
 Function TsvCell(X:LongInt):AnsiString;
 Begin
  Case JP[X].Kind of
   JK_NULL:TsvCell:='';
   JK_BOOL,JK_NUM:TsvCell:=JP[X].S;
   JK_STR:TsvCell:=ReplaceAll(ReplaceAll(ReplaceAll(ReplaceAll(JP[X].S,'\','\\'),#9,'\t'),#10,'\n'),
     #13,'\r');
   Else Begin JqFail(TypeName(X)+' ('+Copy(ToStr(X),1,11)+') is not valid in a tsv row');TsvCell:='';End;
  End;
 End;
Begin
 FmtApply:='';
 If(F='')or(F='text')Then Begin FmtApply:=ToStr(N);Exit;End;
 If F='json' Then Begin FmtApply:=RawJson(N);Exit;End;
 If F='csv' Then Begin
  If JP[N].Kind<>JK_ARR Then Begin JqFail(TypeName(N)+' ('+Copy(ToStr(N),1,11)+') cannot be csv-formatted, only an array can be');Exit;End;
  BufClear(B);First:=True;
  C:=JP[N].First;
  While C>=0 do Begin
   If not First Then BufAdd(B,',');
   First:=False;
   BufAdd(B,CsvCell(C));
   C:=JP[C].Next;
  End;
  FmtApply:=BufStr(B);Exit;
 End;
 If F='tsv' Then Begin
  If JP[N].Kind<>JK_ARR Then Begin JqFail(TypeName(N)+' ('+Copy(ToStr(N),1,11)+') cannot be tsv-formatted, only an array can be');Exit;End;
  BufClear(B);First:=True;
  C:=JP[N].First;
  While C>=0 do Begin
   If not First Then BufAdd(B,#9);
   First:=False;
   BufAdd(B,TsvCell(C));
   C:=JP[C].Next;
  End;
  FmtApply:=BufStr(B);Exit;
 End;
 S:=ToStr(N);
 If F='html' Then Begin
  R:=ReplaceAll(S,'&','&amp;');R:=ReplaceAll(R,'<','&lt;');R:=ReplaceAll(R,'>','&gt;');
  R:=ReplaceAll(R,'''','&#39;');R:=ReplaceAll(R,'"','&quot;');
  FmtApply:=R;Exit;
 End;
 If F='uri' Then Begin FmtApply:=UrlEnc(S,False);Exit;End;
 If F='sh' Then Begin
  If JP[N].Kind=JK_ARR Then Begin
   BufClear(B);First:=True;
   C:=JP[N].First;
   While C>=0 do Begin
    If not First Then BufAdd(B,' ');
    First:=False;
    If JP[C].Kind=JK_STR Then BufAdd(B,''''+ReplaceAll(JP[C].S,'''','''\''''')+'''') Else BufAdd(B,ToStr(C));
    C:=JP[C].Next;
   End;
   FmtApply:=BufStr(B);
  End
  Else If JP[N].Kind=JK_STR Then FmtApply:=''''+ReplaceAll(S,'''','''\''''')+''''
  Else FmtApply:=S;
  Exit;
 End;
 If F='base64' Then Begin FmtApply:=B64Str(S);Exit;End;
 If F='base64d' Then Begin FmtApply:=B64Dec(S);Exit;End;
 JqFail(F+' is not a valid format');
End;

{ ---------- tri ---------- }

Procedure MergeSort(Var Idx:TIList;Const Keys:TIList);
Var
 Tmp:Array of LongInt;
 W,I,L,M,R,A,B,K:LongInt;
Begin
 SetLength(Tmp,Idx.N);
 W:=1;
 While W<Idx.N do Begin
  I:=0;
  While I<Idx.N do Begin
   L:=I;M:=I+W;R:=I+2*W;
   If M>Idx.N Then M:=Idx.N;
   If R>Idx.N Then R:=Idx.N;
   A:=L;B:=M;K:=L;
   While(A<M)and(B<R)do Begin
    If JCmp(Keys.A[Idx.A[B]],Keys.A[Idx.A[A]])<0 Then Begin Tmp[K]:=Idx.A[B];Inc(B);End
    Else Begin Tmp[K]:=Idx.A[A];Inc(A);End;
    Inc(K);
   End;
   While A<M do Begin Tmp[K]:=Idx.A[A];Inc(A);Inc(K);End;
   While B<R do Begin Tmp[K]:=Idx.A[B];Inc(B);Inc(K);End;
   Inc(I,2*W);
  End;
  For I:=0 to Idx.N-1 do Idx.A[I]:=Tmp[I];
  W:=W*2;
 End;
End;

{ elements d'un tableau dans une liste }
Procedure ArrItems(A:LongInt;Var L:TIList);
Var
 C:LongInt;
Begin
 L.N:=0;SetLength(L.A,0);
 If(A<0)or not(JP[A].Kind in[JK_ARR,JK_OBJ])Then Exit;
 C:=JP[A].First;
 While C>=0 do Begin IAdd(L,C);C:=JP[C].Next;End;
End;

{ cles de tri : f evalue sur chaque element (tableau des sorties) }
Procedure SortKeys(Els:TIList;F:LongInt;Var Keys:TIList);
Var
 I,K:LongInt;
 T:TIList;
 J:LongInt;
Begin
 Keys.N:=0;SetLength(Keys.A,0);
 For I:=0 to Els.N-1 do Begin
  If F<0 Then IAdd(Keys,Els.A[I])
  Else Begin
   T.N:=0;SetLength(T.A,0);
   Ev(F,Els.A[I],T);
   K:=MkArr;
   For J:=0 to T.N-1 do ArrAdd(K,T.A[J]);
   IAdd(Keys,K);
  End;
 End;
End;

Function SortedIdx(Els,Keys:TIList):TIList;
Var
 I:LongInt;
Begin
 SortedIdx.N:=0;SetLength(SortedIdx.A,0);
 For I:=0 to Els.N-1 do IAdd(SortedIdx,I);
 MergeSort(SortedIdx,Keys);
End;

{ ---------- regex jq ---------- }

Function MatchObj(Const S:AnsiString;St0:LongInt):LongInt;
Var
 O,Caps,Cp,I:LongInt;
 Off:LongInt;
Begin
 O:=MkObj;
 ObjSet(O,'offset',MkNum(U8Len(Copy(S,1,RxCap[0]-1))));
 ObjSet(O,'length',MkNum(U8Len(Copy(S,RxCap[0],RxCap[1]-RxCap[0]))));
 ObjSet(O,'string',MkStr(Copy(S,RxCap[0],RxCap[1]-RxCap[0])));
 Caps:=MkArr;
 For I:=1 to RxNGroups do Begin
  Cp:=MkObj;
  If(RxCap[I*2]>0)and(RxCap[I*2+1]>0)Then Begin
   ObjSet(Cp,'offset',MkNum(U8Len(Copy(S,1,RxCap[I*2]-1))));
   ObjSet(Cp,'length',MkNum(U8Len(Copy(S,RxCap[I*2],RxCap[I*2+1]-RxCap[I*2]))));
   ObjSet(Cp,'string',MkStr(Copy(S,RxCap[I*2],RxCap[I*2+1]-RxCap[I*2])));
  End
  Else Begin
   ObjSet(Cp,'offset',MkNum(-1));ObjSet(Cp,'length',MkNum(0));ObjSet(Cp,'string',MkNull);
  End;
  If I<=9 Then Begin
   If RxGroupNames[I]<>'' Then ObjSet(Cp,'name',MkStr(RxGroupNames[I])) Else ObjSet(Cp,'name',MkNull);
  End;
  ArrAdd(Caps,Cp);
 End;
 ObjSet(O,'captures',Caps);
 MatchObj:=O;
End;

{ tous les resultats d'une recherche ; Flags : g, i, x }
Procedure RegexMatches(Const S,Pat,Flags:AnsiString;Var L:TIList);
Var
 Pos_,E:LongInt;
Begin
 L.N:=0;SetLength(L.A,0);
 If not RxCompile(Pat,Pos('i',Flags)>0,Pos('x',Flags)>0)Then Begin
  JqFail(Pat+' (at offset 0) is not a valid regex');Exit;
 End;
 Pos_:=1;
 While Pos_<=Length(S)+1 do Begin
  If not RxSearch(S,Pos_)Then Break;
  IAdd(L,MatchObj(S,Pos_));
  If Pos('g',Flags)=0 Then Break;
  E:=RxCap[1];
  If E=RxCap[0]Then Pos_:=E+1 Else Pos_:=E;
 End;
End;

{ ---------- evaluation ---------- }

Procedure EvStrParts(Idx,In_:LongInt;Const Acc:AnsiString;Var Out:TIList);
Var
 T:TIList;
 I:LongInt;
Begin
 If Idx<0 Then Begin IAdd(Out,MkStr(Acc));Exit;End;
 If JqT[Idx].Kd=Q_LIT Then Begin EvStrParts(JqT[Idx].Nx,In_,Acc+JqT[Idx].S,Out);Exit;End;
 T.N:=0;SetLength(T.A,0);
 If JqT[Idx].A<0 Then IAdd(T,In_) Else Ev(JqT[Idx].A,In_,T);
 For I:=0 to T.N-1 do Begin
  If JqErrS<>'' Then Exit;
  EvStrParts(JqT[Idx].Nx,In_,Acc+FmtApply(JqT[Idx].S,T.A[I]),Out);
 End;
End;

Procedure ObjBuild(Ent,In_,Cur:LongInt;Var Out:TIList);
Var
 K,V:TIList;
 I,J,O:LongInt;
Begin
 If Ent<0 Then Begin IAdd(Out,Cur);Exit;End;
 K.N:=0;SetLength(K.A,0);V.N:=0;SetLength(V.A,0);
 Ev(JqT[Ent].A,In_,K);
 For I:=0 to K.N-1 do Begin
  If JqErrS<>'' Then Exit;
  If JP[K.A[I]].Kind<>JK_STR Then Begin
   JqFail('Object keys must be strings');Exit;
  End;
  V.N:=0;
  If JqT[Ent].B<0 Then IAdd(V,In_) Else Ev(JqT[Ent].B,In_,V);
  For J:=0 to V.N-1 do Begin
   O:=Cpy(Cur);
   ObjSet(O,JP[K.A[I]].S,V.A[J]);
   ObjBuild(JqT[Ent].Nx,In_,O,Out);
  End;
 End;
End;

Procedure RecurseAll(N:LongInt;Var Out:TIList);
Var
 C:LongInt;
Begin
 IAdd(Out,N);
 If JP[N].Kind in[JK_ARR,JK_OBJ]Then Begin
  C:=JP[N].First;
  While C>=0 do Begin RecurseAll(C,Out);C:=JP[C].Next;End;
 End;
End;

Function IndexOf(T,I:LongInt):LongInt;
Var
 K:LongInt;
 D:Double;
Begin
 IndexOf:=-1;
 If TypeOrd(T)=0 Then Begin
  If TypeOrd(I)in[0,3,4]Then Begin IndexOf:=MkNull;Exit;End;
 End;
 If(JP[T].Kind=JK_OBJ)and(JP[I].Kind=JK_STR)Then Begin
  K:=JGet(T,JP[I].S);
  If K<0 Then IndexOf:=MkNull Else IndexOf:=K;
  Exit;
 End;
 If(JP[T].Kind=JK_ARR)and(JP[I].Kind=JK_NUM)Then Begin
  D:=NumOf(I);
  K:=Trunc(D);
  If K<0 Then K:=JP[T].Cnt+K;
  If(K<0)or(K>=JP[T].Cnt)Then IndexOf:=MkNull Else IndexOf:=JAt(T,K);
  Exit;
 End;
 If JP[T].Kind=JK_NULL Then Begin IndexOf:=MkNull;Exit;End;
 If JP[I].Kind=JK_STR Then JqFail('Cannot index '+TypeName(T)+' with "'+JP[I].S+'"')
 Else JqFail('Cannot index '+TypeName(T)+' with '+TypeName(I));
End;

Procedure SliceOf(T:LongInt;F,E:LongInt;Var Out:TIList);
Var
 A,B,N,I:LongInt;
 R:LongInt;
Begin
 If TypeOrd(T)=0 Then Begin IAdd(Out,MkNull);Exit;End;
 If JP[T].Kind=JK_STR Then N:=U8Len(JP[T].S)
 Else If JP[T].Kind=JK_ARR Then N:=JP[T].Cnt
 Else Begin JqFail('Cannot index '+TypeName(T)+' with object');Exit;End;
 If F<0 Then A:=0 Else Begin A:=Trunc(NumOf(F));If A<0 Then A:=N+A;End;
 If E<0 Then B:=N Else Begin B:=Trunc(NumOf(E));If B<0 Then B:=N+B;End;
 If A<0 Then A:=0;
 If B>N Then B:=N;
 If B<A Then B:=A;
 If JP[T].Kind=JK_STR Then IAdd(Out,MkStr(U8Sub(JP[T].S,A,B)))
 Else Begin
  R:=MkArr;
  For I:=A to B-1 do ArrAdd(R,JAt(T,I));
  IAdd(Out,R);
 End;
End;

Function EnvNode:LongInt;
Var
 I,P:LongInt;
 S:AnsiString;
Begin
 If EnvNodeCache>=0 Then Begin EnvNode:=EnvNodeCache;Exit;End;
 EnvNodeCache:=MkObj;
 For I:=1 to EnvCount do Begin
  S:=EnvStr(I);
  P:=Pos('=',S);
  If P>1 Then ObjSet(EnvNodeCache,Copy(S,1,P-1),MkStr(Copy(S,P+1,Length(S))));
 End;
 EnvNode:=EnvNodeCache;
End;

Const
 DayNames:Array[0..6]of AnsiString=('Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday');

Function StrftimeImpl(Const Fmt:AnsiString;E:Int64):AnsiString;
Var
 S,R:AnsiString;
 I:LongInt;
 T:AnsiString;
 Days:Int64;
 DW:LongInt;
Begin
 T:=StampToStr(E);
 R:='';
 I:=1;
 While I<=Length(Fmt)do Begin
  If(Fmt[I]='%')and(I<Length(Fmt))Then Begin
   Inc(I);
   Case Fmt[I] of
    'Y':R:=R+Copy(T,1,4);
    'm':R:=R+Copy(T,6,2);
    'd':R:=R+Copy(T,9,2);
    'H':R:=R+Copy(T,12,2);
    'M':R:=R+Copy(T,15,2);
    'S':R:=R+Copy(T,18,2);
    'Z':R:=R+'UTC';
    'z':R:=R+'+0000';
    'y':R:=R+Copy(T,3,2);
    'F':R:=R+Copy(T,1,10);
    'T':R:=R+Copy(T,12,8);
    'D':R:=R+Copy(T,6,2)+'/'+Copy(T,9,2)+'/'+Copy(T,3,2);
    's':R:=R+IStr(E);
    'e':R:=R+IStr(ToInt(Copy(T,9,2),0));
    'j':Begin
         Days:=DaysFromCivil(ToInt(Copy(T,1,4),1970),ToInt(Copy(T,6,2),1),ToInt(Copy(T,9,2),1))-
           DaysFromCivil(ToInt(Copy(T,1,4),1970),1,1)+1;
         S:=IStr(Days);
         While Length(S)<3 do S:='0'+S;
         R:=R+S;
        End;
    'A','a':Begin
             DW:=((E div 86400)+4)mod 7;
             If DW<0 Then DW:=DW+7;
             If Fmt[I]='A' Then R:=R+DayNames[DW] Else R:=R+Copy(DayNames[DW],1,3);
            End;
    '%':R:=R+'%';
    Else R:=R+'%'+Fmt[I];
   End;
  End
  Else R:=R+Fmt[I];
  Inc(I);
 End;
 StrftimeImpl:=R;
End;

{ ------------------------------------------------------------------ }
{ jq : chemins, fonctions integrees, boucle d'evaluation              }
{ ------------------------------------------------------------------ }

Function ArrOfList(Const L:TIList):LongInt;
Var
 R,I:LongInt;
Begin
 R:=MkArr;
 For I:=0 to L.N-1 do ArrAdd(R,L.A[I]);
 ArrOfList:=R;
End;

{ valeur a un chemin (tableau de cles) }
Function GetAt(Root,Path:LongInt):LongInt;
Var
 C:LongInt;
 V:LongInt;
Begin
 V:=Root;
 C:=JP[Path].First;
 While C>=0 do Begin
  If TypeOrd(V)=0 Then Begin GetAt:=MkNull;Exit;End;
  V:=IndexOf(V,C);
  If(V<0)or(JqErrS<>'')Then Begin GetAt:=MkNull;Exit;End;
  C:=JP[C].Next;
 End;
 GetAt:=V;
End;

{ copie de Root dont le chemin Path (a partir de l'element C) vaut V }
Function SetFrom(Root,C,V:LongInt):LongInt;
Var
 R,Child,Nx,I,K:LongInt;
Begin
 If C<0 Then Begin SetFrom:=Cpy(V);Exit;End;
 Nx:=JP[C].Next;
 If JP[C].Kind=JK_STR Then Begin
  If TypeOrd(Root)=0 Then R:=MkObj
  Else If JP[Root].Kind=JK_OBJ Then R:=Cpy(Root)
  Else Begin JqFail('Cannot index '+TypeName(Root)+' with "'+JP[C].S+'"');SetFrom:=MkNull;Exit;End;
  Child:=JGet(R,JP[C].S);
  If Child<0 Then Child:=MkNull;
  ObjSet(R,JP[C].S,SetFrom(Child,Nx,V));
  SetFrom:=R;
 End
 Else If JP[C].Kind=JK_NUM Then Begin
  If TypeOrd(Root)=0 Then R:=MkArr
  Else If JP[Root].Kind=JK_ARR Then R:=Cpy(Root)
  Else Begin JqFail('Cannot index '+TypeName(Root)+' with number');SetFrom:=MkNull;Exit;End;
  K:=Trunc(NumOf(C));
  If K<0 Then K:=JP[R].Cnt+K;
  If K<0 Then Begin JqFail('Out of bounds negative array index');SetFrom:=R;Exit;End;
  While JP[R].Cnt<=K do JAppend(R,MkNull);
  Child:=JAt(R,K);
  { reconstruit le tableau avec l'element remplace }
  Child:=SetFrom(Child,Nx,V);
  Root:=R;
  R:=MkArr;
  For I:=0 to JP[Root].Cnt-1 do
   If I=K Then ArrAdd(R,Child) Else ArrAdd(R,JAt(Root,I));
  SetFrom:=R;
 End
 Else Begin JqFail('Invalid path component');SetFrom:=MkNull;End;
End;

Function SetAt(Root,Path,V:LongInt):LongInt;
Begin
 SetAt:=SetFrom(Root,JP[Path].First,V);
End;

{ chemins d'une expression de chemin : ajoute (valeur, chemin) }
Procedure PathEval(P,Val,Path:LongInt;Var Vals,Paths:TIList);
Var
 T1,T2,PT,VT:TIList;
 I,J,C,K,NP:LongInt;
 Idx:TIList;
 Function Ext(Pa,Key:LongInt):LongInt;
 Var
  R:LongInt;
 Begin
  R:=Cpy(Pa);
  ArrAdd(R,Key);
  Ext:=R;
 End;
Begin
 If JqErrS<>'' Then Exit;
 T1.N:=0;T2.N:=0;PT.N:=0;VT.N:=0;Idx.N:=0;
 Case JqT[P].Kd of
  Q_ID:Begin IAdd(Vals,Val);IAdd(Paths,Path);End;
  Q_PIPE:Begin
   T1.N:=0;SetLength(T1.A,0);PT.N:=0;SetLength(PT.A,0);
   PathEval(JqT[P].A,Val,Path,T1,PT);
   For I:=0 to T1.N-1 do PathEval(JqT[P].B,T1.A[I],PT.A[I],Vals,Paths);
  End;
  Q_COMMA:Begin
   PathEval(JqT[P].A,Val,Path,Vals,Paths);
   PathEval(JqT[P].B,Val,Path,Vals,Paths);
  End;
  Q_FIELD,Q_INDEX:Begin
   T1.N:=0;SetLength(T1.A,0);PT.N:=0;SetLength(PT.A,0);
   PathEval(JqT[P].A,Val,Path,T1,PT);
   For I:=0 to T1.N-1 do Begin
    If JqT[P].Kd=Q_FIELD Then Begin
     If TypeOrd(T1.A[I])=0 Then Begin IAdd(Vals,MkNull);IAdd(Paths,Ext(PT.A[I],MkStr(JqT[P].S)));End
     Else If JP[T1.A[I]].Kind<>JK_OBJ Then Begin
      JqFail('Cannot index '+TypeName(T1.A[I])+' with "'+JqT[P].S+'"');Exit;
     End
     Else Begin
      K:=JGet(T1.A[I],JqT[P].S);
      If K<0 Then K:=MkNull;
      IAdd(Vals,K);IAdd(Paths,Ext(PT.A[I],MkStr(JqT[P].S)));
     End;
    End
    Else Begin
     T2.N:=0;SetLength(T2.A,0);
     Ev(JqT[P].B,Val,T2);
     For J:=0 to T2.N-1 do Begin
      K:=IndexOf(T1.A[I],T2.A[J]);
      If JqErrS<>'' Then Exit;
      IAdd(Vals,K);IAdd(Paths,Ext(PT.A[I],T2.A[J]));
     End;
    End;
   End;
  End;
  Q_ITER:Begin
   T1.N:=0;SetLength(T1.A,0);PT.N:=0;SetLength(PT.A,0);
   PathEval(JqT[P].A,Val,Path,T1,PT);
   For I:=0 to T1.N-1 do Begin
    If not(JP[T1.A[I]].Kind in[JK_ARR,JK_OBJ])Then Begin
     JqFail('Cannot iterate over '+TypeName(T1.A[I]));Exit;
    End;
    C:=JP[T1.A[I]].First;K:=0;
    While C>=0 do Begin
     IAdd(Vals,C);
     If JP[T1.A[I]].Kind=JK_OBJ Then IAdd(Paths,Ext(PT.A[I],MkStr(JP[C].Key)))
     Else IAdd(Paths,Ext(PT.A[I],MkNum(K)));
     Inc(K);
     C:=JP[C].Next;
    End;
   End;
  End;
  Q_REC:Begin
   T1.N:=0;SetLength(T1.A,0);
   RecurseAll(Val,T1);
   { reconstitue les chemins par parcours }
   PT.N:=0;SetLength(PT.A,0);
   IAdd(Vals,Val);IAdd(Paths,Path);
   If JP[Val].Kind in[JK_ARR,JK_OBJ]Then Begin
    C:=JP[Val].First;K:=0;
    While C>=0 do Begin
     If JP[Val].Kind=JK_OBJ Then NP:=Ext(Path,MkStr(JP[C].Key)) Else NP:=Ext(Path,MkNum(K));
     T2.N:=0;SetLength(T2.A,0);
     PathEval(P,C,NP,Vals,Paths);
     Inc(K);
     C:=JP[C].Next;
    End;
   End;
  End;
  Q_TRY:Begin
   PathEval(JqT[P].A,Val,Path,Vals,Paths);
   If JqErrS<>'' Then JqErrS:='';
  End;
  Q_IF:Begin
   T1.N:=0;SetLength(T1.A,0);
   Ev(JqT[P].A,Val,T1);
   For I:=0 to T1.N-1 do
    If Truthy(T1.A[I])Then PathEval(JqT[P].B,Val,Path,Vals,Paths)
    Else PathEval(JqT[P].C,Val,Path,Vals,Paths);
  End;
  Q_ALT:Begin
   T1.N:=0;SetLength(T1.A,0);PT.N:=0;SetLength(PT.A,0);
   PathEval(JqT[P].A,Val,Path,T1,PT);
   K:=0;
   For I:=0 to T1.N-1 do If Truthy(T1.A[I])Then Begin IAdd(Vals,T1.A[I]);IAdd(Paths,PT.A[I]);Inc(K);End;
   If K=0 Then PathEval(JqT[P].B,Val,Path,Vals,Paths);
  End;
  Q_FUNC:Begin
   If JqT[P].S='empty' Then Exit;
   If(JqT[P].S='select')and(Trunc(JqT[P].D)=1)Then Begin
    T1.N:=0;SetLength(T1.A,0);
    Ev(JqT[P].A,Val,T1);
    For I:=0 to T1.N-1 do If Truthy(T1.A[I])Then Begin IAdd(Vals,Val);IAdd(Paths,Path);End;
    Exit;
   End;
   If(JqT[P].S='recurse')and(Trunc(JqT[P].D)=0)Then Begin
    K:=QNew(Q_REC,'',-1,-1,-1);
    PathEval(K,Val,Path,Vals,Paths);
    Exit;
   End;
   If(JqT[P].S='first')and(Trunc(JqT[P].D)=0)Then Begin
    K:=QNew(Q_INDEX,'',QNew(Q_ID,'',-1,-1,-1),QNew(Q_NUM,'0',-1,-1,-1),-1);
    PathEval(K,Val,Path,Vals,Paths);Exit;
   End;
   If(JqT[P].S='last')and(Trunc(JqT[P].D)=0)Then Begin
    K:=QNew(Q_INDEX,'',QNew(Q_ID,'',-1,-1,-1),QNew(Q_NUM,'-1',-1,-1,-1),-1);
    PathEval(K,Val,Path,Vals,Paths);Exit;
   End;
   JqFail('Invalid path expression with result '+Copy(ToStr(Val),1,11));
  End;
  Else JqFail('Invalid path expression');
 End;
End;

{ supprime les chemins (copie) }
Function DelPaths(Root:LongInt;Const Paths:TIList):LongInt;
Var
 Idx,Keys:TIList;
 I,J,R,Last,K,Par,NewPar,C:LongInt;
 PathNode:LongInt;
 Function DelOne(V,C:LongInt;Pa:LongInt):LongInt;
 Var
  Nx,Res,Ch,X,Ix,N2:LongInt;
 Begin
  If TypeOrd(V)=0 Then Begin DelOne:=V;Exit;End;
  Nx:=JP[C].Next;
  If Nx<0 Then Begin
   { suppression finale }
   If(JP[V].Kind=JK_OBJ)and(JP[C].Kind=JK_STR)Then Begin
    Res:=MkObj;
    X:=JP[V].First;
    While X>=0 do Begin
     If JP[X].Key<>JP[C].S Then ObjSet(Res,JP[X].Key,X);
     X:=JP[X].Next;
    End;
    DelOne:=Res;Exit;
   End;
   If(JP[V].Kind=JK_ARR)and(JP[C].Kind=JK_NUM)Then Begin
    Ix:=Trunc(NumOf(C));
    If Ix<0 Then Ix:=JP[V].Cnt+Ix;
    Res:=MkArr;
    N2:=0;
    X:=JP[V].First;
    While X>=0 do Begin
     If N2<>Ix Then ArrAdd(Res,X);
     Inc(N2);
     X:=JP[X].Next;
    End;
    DelOne:=Res;Exit;
   End;
   DelOne:=V;Exit;
  End;
  If(JP[V].Kind=JK_OBJ)and(JP[C].Kind=JK_STR)Then Begin
   Ch:=JGet(V,JP[C].S);
   If Ch<0 Then Begin DelOne:=V;Exit;End;
   Res:=Cpy(V);
   ObjSet(Res,JP[C].S,DelOne(Ch,Nx,Pa));
   DelOne:=Res;Exit;
  End;
  If(JP[V].Kind=JK_ARR)and(JP[C].Kind=JK_NUM)Then Begin
   Ix:=Trunc(NumOf(C));
   If Ix<0 Then Ix:=JP[V].Cnt+Ix;
   Res:=MkArr;N2:=0;
   X:=JP[V].First;
   While X>=0 do Begin
    If N2=Ix Then ArrAdd(Res,DelOne(X,Nx,Pa)) Else ArrAdd(Res,X);
    Inc(N2);
    X:=JP[X].Next;
   End;
   DelOne:=Res;Exit;
  End;
  DelOne:=V;
 End;
Begin
 { trie les chemins par ordre decroissant pour supprimer les indices eleves d'abord }
 Keys.N:=0;SetLength(Keys.A,0);
 For I:=0 to Paths.N-1 do IAdd(Keys,Paths.A[I]);
 Idx.N:=0;SetLength(Idx.A,0);
 For I:=0 to Paths.N-1 do IAdd(Idx,I);
 MergeSort(Idx,Keys);
 R:=Root;
 For I:=Idx.N-1 downto 0 do Begin
  PathNode:=Paths.A[Idx.A[I]];
  If JP[PathNode].Cnt=0 Then Begin R:=MkNull;Continue;End;
  R:=DelOne(R,JP[PathNode].First,PathNode);
 End;
 DelPaths:=R;
End;

{ ---------- fonctions integrees ---------- }

Procedure ToEntries(N:LongInt;Var Out:TIList);
Var
 R,E,C,K:LongInt;
Begin
 R:=MkArr;
 If JP[N].Kind=JK_ARR Then Begin
  C:=JP[N].First;K:=0;
  While C>=0 do Begin
   E:=MkObj;
   ObjSet(E,'key',MkNum(K));
   ObjSet(E,'value',C);
   ArrAdd(R,E);
   Inc(K);C:=JP[C].Next;
  End;
 End
 Else If JP[N].Kind=JK_OBJ Then Begin
  C:=JP[N].First;
  While C>=0 do Begin
   E:=MkObj;
   ObjSet(E,'key',MkStr(JP[C].Key));
   ObjSet(E,'value',C);
   ArrAdd(R,E);
   C:=JP[C].Next;
  End;
 End
 Else Begin JqFail(TypeName(N)+' ('+Copy(ToStr(N),1,11)+') has no keys');Exit;End;
 IAdd(Out,R);
End;

Procedure FromEntries(N:LongInt;Var Out:TIList);
Var
 R,C,K,V:LongInt;
 Ks:AnsiString;
 Function Pick(E:LongInt;Const Names:AnsiString):LongInt;
 Var
  L:TSList;
  I:LongInt;
 Begin
  Pick:=-1;
  SplitStr(Names,',',L);
  For I:=0 to L.N-1 do If JGet(E,L.A[I])>=0 Then Begin
   If TypeOrd(JGet(E,L.A[I]))<>0 Then Begin Pick:=JGet(E,L.A[I]);Exit;End;
  End;
 End;
Begin
 R:=MkObj;
 If not(JP[N].Kind in[JK_ARR,JK_OBJ])Then Begin JqFail('Cannot iterate over '+TypeName(N));Exit;End;
 C:=JP[N].First;
 While C>=0 do Begin
  K:=Pick(C,'key,k,name,Name,Key,K');
  V:=Pick(C,'value,v,Value,V');
  If K<0 Then Ks:='null'
  Else If JP[K].Kind=JK_STR Then Ks:=JP[K].S
  Else Ks:=ToStr(K);
  If V<0 Then V:=MkNull;
  ObjSet(R,Ks,V);
  C:=JP[C].Next;
 End;
 IAdd(Out,R);
End;

Procedure FlattenInto(N:LongInt;Depth:LongInt;R:LongInt);
Var
 C:LongInt;
Begin
 C:=JP[N].First;
 While C>=0 do Begin
  If(JP[C].Kind=JK_ARR)and(Depth>0)Then FlattenInto(C,Depth-1,R) Else ArrAdd(R,C);
  C:=JP[C].Next;
 End;
End;

Function ContainsV(A,B:LongInt):Boolean;
Var
 C,D:LongInt;
 Found:Boolean;
Begin
 ContainsV:=False;
 If(JP[A].Kind=JK_OBJ)and(JP[B].Kind=JK_OBJ)Then Begin
  D:=JP[B].First;
  While D>=0 do Begin
   C:=JGet(A,JP[D].Key);
   If(C<0)or not ContainsV(C,D)Then Exit;
   D:=JP[D].Next;
  End;
  ContainsV:=True;Exit;
 End;
 If(JP[A].Kind=JK_ARR)and(JP[B].Kind=JK_ARR)Then Begin
  D:=JP[B].First;
  While D>=0 do Begin
   Found:=False;
   C:=JP[A].First;
   While C>=0 do Begin
    If(TypeOrd(C)=TypeOrd(D))or((JP[C].Kind=JK_BOOL)and(JP[D].Kind=JK_BOOL))Then
      If ContainsV(C,D)Then Found:=True;
    C:=JP[C].Next;
   End;
   If not Found Then Exit;
   D:=JP[D].Next;
  End;
  ContainsV:=True;Exit;
 End;
 If(JP[A].Kind=JK_STR)and(JP[B].Kind=JK_STR)Then Begin ContainsV:=Pos(JP[B].S,JP[A].S)>0;Exit;End;
 ContainsV:=JCmp(A,B)=0;
End;

Procedure EvFunc(P,In_:LongInt;Var Out:TIList);
Var
 Nm:AnsiString;
 NA,A,B,C:LongInt;
 T,T2,Els,Keys,Idx:TIList;
 I,J,K,N,R,X,Y:LongInt;
 S,S2,Fl:AnsiString;
 D:Double;
 Ok:Boolean;
 Procedure MathFn(Fn:Byte);
 Begin
  If(In_<0)or(JP[In_].Kind<>JK_NUM)Then Begin
   JqFail(TypeName(In_)+' ('+Copy(ToStr(In_),1,11)+') number required');Exit;
  End;
  D:=NumOf(In_);
  Case Fn of
   1:D:=Int(D)-Ord((D<0)and(Frac(D)<>0));
   2:D:=Int(D)+Ord((D>0)and(Frac(D)<>0));
   3:If D<0 Then D:=-Int(-D+0.5) Else D:=Int(D+0.5);
   4:If D<0 Then Begin JqFail('number ('+ToStr(In_)+') cannot be square-rooted');Exit;End Else D:=Sqrt(D);
   5:D:=Abs(D);
   6:D:=Ln(D);
   7:D:=Exp(D);
  End;
  IAdd(Out,MkNum(D));
 End;
 Procedure Sel(Const Kinds:AnsiString);
 Begin
  If Pos(TypeName(In_),Kinds)>0 Then IAdd(Out,In_);
 End;
Begin
 Nm:=JqT[P].S;NA:=Trunc(JqT[P].D);
 A:=JqT[P].A;B:=JqT[P].B;C:=JqT[P].C;
 T.N:=0;T2.N:=0;Els.N:=0;Keys.N:=0;Idx.N:=0;
 If NA=0 Then Begin
  If Nm='empty' Then Exit;
  If Nm='not' Then Begin IAdd(Out,MkBool(not Truthy(In_)));Exit;End;
  If Nm='length' Then Begin
   Case TypeOrd(In_)of
    0:IAdd(Out,MkNum(0));
    1,2:JqFail('boolean ('+ToStr(In_)+') has no length');
    3:IAdd(Out,MkNum(Abs(NumOf(In_))));
    4:IAdd(Out,MkNum(U8Len(JP[In_].S)));
    Else IAdd(Out,MkNum(JP[In_].Cnt));
   End;
   Exit;
  End;
  If Nm='utf8bytelength' Then Begin IAdd(Out,MkNum(Length(ToStr(In_))));Exit;End;
  If(Nm='keys')or(Nm='keys_unsorted')Then Begin
   If JP[In_].Kind=JK_OBJ Then Begin
    R:=MkArr;
    X:=JP[In_].First;
    If Nm='keys' Then Begin
     Keys.N:=0;SetLength(Keys.A,0);
     While X>=0 do Begin IAdd(Keys,MkStr(JP[X].Key));X:=JP[X].Next;End;
     Idx.N:=0;SetLength(Idx.A,0);
     For I:=0 to Keys.N-1 do IAdd(Idx,I);
     MergeSort(Idx,Keys);
     For I:=0 to Idx.N-1 do ArrAdd(R,Keys.A[Idx.A[I]]);
    End
    Else While X>=0 do Begin ArrAdd(R,MkStr(JP[X].Key));X:=JP[X].Next;End;
    IAdd(Out,R);
   End
   Else If JP[In_].Kind=JK_ARR Then Begin
    R:=MkArr;
    For I:=0 to JP[In_].Cnt-1 do ArrAdd(R,MkNum(I));
    IAdd(Out,R);
   End
   Else JqFail(TypeName(In_)+' ('+Copy(ToStr(In_),1,11)+') has no keys');
   Exit;
  End;
  If Nm='values' Then Begin If TypeOrd(In_)<>0 Then IAdd(Out,In_);Exit;End;
  If Nm='nulls' Then Begin If TypeOrd(In_)=0 Then IAdd(Out,In_);Exit;End;
  If Nm='arrays' Then Begin Sel('array');Exit;End;
  If Nm='objects' Then Begin Sel('object');Exit;End;
  If Nm='strings' Then Begin Sel('string');Exit;End;
  If Nm='numbers' Then Begin Sel('number');Exit;End;
  If Nm='booleans' Then Begin Sel('boolean');Exit;End;
  If Nm='iterables' Then Begin If JP[In_].Kind in[JK_ARR,JK_OBJ]Then IAdd(Out,In_);Exit;End;
  If Nm='scalars' Then Begin If not(JP[In_].Kind in[JK_ARR,JK_OBJ])Then IAdd(Out,In_);Exit;End;
  If Nm='add' Then Begin
   ArrItems(In_,Els);
   If(In_>=0)and not(JP[In_].Kind in[JK_ARR,JK_OBJ])Then Begin
    JqFail('Cannot iterate over '+TypeName(In_));Exit;
   End;
   R:=MkNull;
   For I:=0 to Els.N-1 do Begin
    R:=BinOp('+',R,Els.A[I]);
    If JqErrS<>'' Then Exit;
   End;
   IAdd(Out,R);Exit;
  End;
  If(Nm='any')or(Nm='all')Then Begin
   ArrItems(In_,Els);
   Ok:=Nm='all';
   For I:=0 to Els.N-1 do
    If Nm='any' Then Begin If Truthy(Els.A[I])Then Ok:=True;End
    Else If not Truthy(Els.A[I])Then Ok:=False;
   IAdd(Out,MkBool(Ok));Exit;
  End;
  If Nm='flatten' Then Begin
   If JP[In_].Kind<>JK_ARR Then Begin JqFail('Cannot iterate over '+TypeName(In_));Exit;End;
   R:=MkArr;FlattenInto(In_,1000,R);IAdd(Out,R);Exit;
  End;
  If Nm='reverse' Then Begin
   If JP[In_].Kind=JK_STR Then Begin
    S:='';
    For I:=U8Len(JP[In_].S)-1 downto 0 do S:=S+U8Sub(JP[In_].S,I,I+1);
    IAdd(Out,MkStr(S));
   End
   Else If TypeOrd(In_)=0 Then IAdd(Out,MkArr)
   Else If JP[In_].Kind=JK_ARR Then Begin
    R:=MkArr;
    For I:=JP[In_].Cnt-1 downto 0 do ArrAdd(R,JAt(In_,I));
    IAdd(Out,R);
   End
   Else JqFail('Cannot reverse '+TypeName(In_));
   Exit;
  End;
  If(Nm='sort')or(Nm='unique')Then Begin
   If JP[In_].Kind<>JK_ARR Then Begin JqFail(TypeName(In_)+' ('+Copy(ToStr(In_),1,11)+') cannot be sorted, as it is not an array');Exit;End;
   ArrItems(In_,Els);
   Idx:=SortedIdx(Els,Els);
   R:=MkArr;
   For I:=0 to Idx.N-1 do Begin
    If(Nm='unique')and(I>0)and(JCmp(Els.A[Idx.A[I]],Els.A[Idx.A[I-1]])=0)Then Continue;
    ArrAdd(R,Els.A[Idx.A[I]]);
   End;
   IAdd(Out,R);Exit;
  End;
  If(Nm='min')or(Nm='max')Then Begin
   ArrItems(In_,Els);
   If Els.N=0 Then Begin IAdd(Out,MkNull);Exit;End;
   X:=Els.A[0];
   For I:=1 to Els.N-1 do
    If Nm='min' Then Begin If JCmp(Els.A[I],X)<0 Then X:=Els.A[I];End
    Else If JCmp(Els.A[I],X)>=0 Then X:=Els.A[I];
   IAdd(Out,X);Exit;
  End;
  If Nm='to_entries' Then Begin ToEntries(In_,Out);Exit;End;
  If Nm='from_entries' Then Begin FromEntries(In_,Out);Exit;End;
  If Nm='tostring' Then Begin IAdd(Out,MkStr(ToStr(In_)));Exit;End;
  If Nm='tojson' Then Begin IAdd(Out,MkStr(RawJson(In_)));Exit;End;
  If Nm='fromjson' Then Begin
   If JP[In_].Kind<>JK_STR Then Begin JqFail(TypeName(In_)+' cannot be parsed as JSON');Exit;End;
   R:=JParse(JP[In_].S);
   If R<0 Then JqFail(JP[In_].S+' (while parsing ''' +JP[In_].S+''')') Else IAdd(Out,R);
   Exit;
  End;
  If Nm='tonumber' Then Begin
   If JP[In_].Kind=JK_NUM Then IAdd(Out,In_)
   Else If JP[In_].Kind=JK_STR Then Begin
    Val(TrimStr(JP[In_].S),D,K);
    If(K<>0)or(TrimStr(JP[In_].S)='')Then JqFail('Cannot parse '''+JP[In_].S+''' as number')
    Else IAdd(Out,MkNum(D));
   End
   Else JqFail(TypeName(In_)+' ('+Copy(ToStr(In_),1,11)+') cannot be parsed as a number');
   Exit;
  End;
  If Nm='type' Then Begin IAdd(Out,MkStr(TypeName(In_)));Exit;End;
  If Nm='ascii_downcase' Then Begin
   If JP[In_].Kind<>JK_STR Then Begin JqFail('ascii_downcase input must be a string');Exit;End;
   IAdd(Out,MkStr(LoStr(JP[In_].S)));Exit;
  End;
  If Nm='ascii_upcase' Then Begin
   If JP[In_].Kind<>JK_STR Then Begin JqFail('ascii_upcase input must be a string');Exit;End;
   IAdd(Out,MkStr(UpStr(JP[In_].S)));Exit;
  End;
  If(Nm='trim')or(Nm='ltrim')or(Nm='rtrim')Then Begin
   If JP[In_].Kind<>JK_STR Then Begin JqFail('trim input must be a string');Exit;End;
   S:=JP[In_].S;
   If Nm<>'rtrim' Then While(S<>'')and(S[1]in[#9,#10,#13,' '])do Delete(S,1,1);
   If Nm<>'ltrim' Then While(S<>'')and(S[Length(S)]in[#9,#10,#13,' '])do Delete(S,Length(S),1);
   IAdd(Out,MkStr(S));Exit;
  End;
  If Nm='floor' Then Begin MathFn(1);Exit;End;
  If Nm='ceil' Then Begin MathFn(2);Exit;End;
  If Nm='round' Then Begin MathFn(3);Exit;End;
  If Nm='sqrt' Then Begin MathFn(4);Exit;End;
  If(Nm='fabs')or(Nm='abs')Then Begin MathFn(5);Exit;End;
  If Nm='log' Then Begin MathFn(6);Exit;End;
  If Nm='exp' Then Begin MathFn(7);Exit;End;
  If Nm='first' Then Begin
   If JP[In_].Kind=JK_ARR Then Begin If JP[In_].Cnt>0 Then IAdd(Out,JP[In_].First) Else IAdd(Out,MkNull);End
   Else IAdd(Out,MkNull);
   Exit;
  End;
  If Nm='last' Then Begin
   If JP[In_].Kind=JK_ARR Then Begin If JP[In_].Cnt>0 Then IAdd(Out,JP[In_].Last) Else IAdd(Out,MkNull);End
   Else IAdd(Out,MkNull);
   Exit;
  End;
  If Nm='now' Then Begin IAdd(Out,MkNum(NowEpoch));Exit;End;
  If(Nm='fromdate')or(Nm='fromdateiso8601')Then Begin
   If JP[In_].Kind<>JK_STR Then Begin JqFail('strptime/1 requires string inputs and arguments');Exit;End;
   IAdd(Out,MkNum(IsoToEpoch(JP[In_].S)));Exit;
  End;
  If(Nm='todate')or(Nm='todateiso8601')or(Nm='date')Then Begin
   If JP[In_].Kind<>JK_NUM Then Begin JqFail('strftime/1 requires parsed datetime inputs');Exit;End;
   IAdd(Out,MkStr(EpochToIso(Trunc(NumOf(In_)))));Exit;
  End;
  If Nm='env' Then Begin IAdd(Out,EnvNode);Exit;End;
  If Nm='infinite' Then Begin IAdd(Out,MkNum(1E300));Exit;End;
  If Nm='nan' Then Begin IAdd(Out,MkNull);Exit;End;
  If Nm='isnan' Then Begin IAdd(Out,MkBool(False));Exit;End;
  If(Nm='isinfinite')Then Begin IAdd(Out,MkBool(False));Exit;End;
  If Nm='isnormal' Then Begin IAdd(Out,MkBool((JP[In_].Kind=JK_NUM)and(NumOf(In_)<>0)));Exit;End;
  If Nm='explode' Then Begin
   S:=ToStr(In_);R:=MkArr;
   I:=1;
   While I<=Length(S)do Begin
    X:=Ord(S[I]);N:=1;
    If X>=$F0 Then Begin X:=X and 7;N:=4;End
    Else If X>=$E0 Then Begin X:=X and 15;N:=3;End
    Else If X>=$C0 Then Begin X:=X and 31;N:=2;End;
    For J:=1 to N-1 do If I+J<=Length(S)Then X:=(X shl 6)or(Ord(S[I+J])and 63);
    ArrAdd(R,MkNum(X));
    Inc(I,N);
   End;
   IAdd(Out,R);Exit;
  End;
  If Nm='implode' Then Begin
   S:='';
   X:=JP[In_].First;
   While X>=0 do Begin S:=S+Utf8Enc(Trunc(NumOf(X)));X:=JP[X].Next;End;
   IAdd(Out,MkStr(S));Exit;
  End;
  If Nm='recurse' Then Begin RecurseAll(In_,Out);Exit;End;
  If Nm='transpose' Then Begin
   N:=0;
   X:=JP[In_].First;
   While X>=0 do Begin If JP[X].Cnt>N Then N:=JP[X].Cnt;X:=JP[X].Next;End;
   R:=MkArr;
   For I:=0 to N-1 do Begin
    Y:=MkArr;
    X:=JP[In_].First;
    While X>=0 do Begin
     If I<JP[X].Cnt Then ArrAdd(Y,JAt(X,I)) Else ArrAdd(Y,MkNull);
     X:=JP[X].Next;
    End;
    ArrAdd(R,Y);
   End;
   IAdd(Out,R);Exit;
  End;
  If(Nm='paths')or(Nm='leaf_paths')Then Begin
   Els.N:=0;SetLength(Els.A,0);Keys.N:=0;SetLength(Keys.A,0);
   X:=QNew(Q_REC,'',-1,-1,-1);
   PathEval(X,In_,MkArr,Els,Keys);
   For I:=1 to Keys.N-1 do
    If(Nm='paths')or not(JP[Els.A[I]].Kind in[JK_ARR,JK_OBJ])Then IAdd(Out,Keys.A[I]);
   Exit;
  End;
  If Nm='toarray' Then Begin
   If JP[In_].Kind=JK_ARR Then IAdd(Out,In_) Else Begin R:=MkArr;ArrAdd(R,In_);IAdd(Out,R);End;
   Exit;
  End;
  If Nm='error' Then Begin JqFail(ToStr(In_));Exit;End;
  If Nm='halt' Then Begin Halt(0);End;
  If(Nm='debug')or(Nm='stderr')Then Begin IAdd(Out,In_);Exit;End;
  If Nm='input' Then Begin JqFail('No more inputs');Exit;End;
  If Nm='ascii' Then Begin IAdd(Out,MkStr(Chr(Trunc(NumOf(In_)))));Exit;End;
  If Nm='tostream' Then Begin IAdd(Out,In_);Exit;End;
 End;
 { --- une ou plusieurs entrees --- }
 If NA>=1 Then Begin
  If Nm='select' Then Begin
   Ev(A,In_,T);
   For I:=0 to T.N-1 do If Truthy(T.A[I])Then IAdd(Out,In_);
   Exit;
  End;
  If Nm='map' Then Begin
   If not(JP[In_].Kind in[JK_ARR,JK_OBJ])Then Begin JqFail('Cannot iterate over '+TypeName(In_));Exit;End;
   ArrItems(In_,Els);
   R:=MkArr;
   For I:=0 to Els.N-1 do Begin
    T.N:=0;
    Ev(A,Els.A[I],T);
    If JqErrS<>'' Then Exit;
    For J:=0 to T.N-1 do ArrAdd(R,T.A[J]);
   End;
   IAdd(Out,R);Exit;
  End;
  If Nm='map_values' Then Begin
   ArrItems(In_,Els);
   If JP[In_].Kind=JK_OBJ Then R:=MkObj Else R:=MkArr;
   For I:=0 to Els.N-1 do Begin
    T.N:=0;
    Ev(A,Els.A[I],T);
    If JqErrS<>'' Then Exit;
    If T.N>0 Then Begin
     If JP[In_].Kind=JK_OBJ Then ObjSet(R,JP[Els.A[I]].Key,T.A[0]) Else ArrAdd(R,T.A[0]);
    End;
   End;
   IAdd(Out,R);Exit;
  End;
  If Nm='recurse' Then Begin
   { recurse(f) : sortie, puis recursion sur les sorties de f }
   Els.N:=0;IAdd(Els,In_);
   I:=0;
   While(I<Els.N)and(I<100000)do Begin
    IAdd(Out,Els.A[I]);
    T.N:=0;
    Ev(A,Els.A[I],T);
    If JqErrS<>'' Then Exit;
    For J:=0 to T.N-1 do IAdd(Els,T.A[J]);
    Inc(I);
   End;
   Exit;
  End;
  If(Nm='has')Then Begin
   Ev(A,In_,T);
   For I:=0 to T.N-1 do Begin
    If(JP[In_].Kind=JK_OBJ)and(JP[T.A[I]].Kind=JK_STR)Then IAdd(Out,MkBool(JGet(In_,JP[T.A[I]].S)>=0))
    Else If(JP[In_].Kind=JK_ARR)and(JP[T.A[I]].Kind=JK_NUM)Then
      IAdd(Out,MkBool((NumOf(T.A[I])>=0)and(NumOf(T.A[I])<JP[In_].Cnt)))
    Else JqFail('Cannot check whether '+TypeName(In_)+' has a '+TypeName(T.A[I])+' key');
   End;
   Exit;
  End;
  If(Nm='in')Then Begin
   Ev(A,In_,T);
   For I:=0 to T.N-1 do Begin
    If(JP[T.A[I]].Kind=JK_OBJ)and(JP[In_].Kind=JK_STR)Then IAdd(Out,MkBool(JGet(T.A[I],JP[In_].S)>=0))
    Else If(JP[T.A[I]].Kind=JK_ARR)and(JP[In_].Kind=JK_NUM)Then
      IAdd(Out,MkBool((NumOf(In_)>=0)and(NumOf(In_)<JP[T.A[I]].Cnt)))
    Else JqFail('Cannot check whether '+TypeName(T.A[I])+' has a '+TypeName(In_)+' key');
   End;
   Exit;
  End;
  If(Nm='contains')or(Nm='inside')Then Begin
   Ev(A,In_,T);
   For I:=0 to T.N-1 do
    If Nm='contains' Then IAdd(Out,MkBool(ContainsV(In_,T.A[I])))
    Else IAdd(Out,MkBool(ContainsV(T.A[I],In_)));
   Exit;
  End;
  If(Nm='startswith')or(Nm='endswith')or(Nm='ltrimstr')or(Nm='rtrimstr')or(Nm='trimstr')Then Begin
   Ev(A,In_,T);
   For I:=0 to T.N-1 do Begin
    If(JP[In_].Kind<>JK_STR)or(JP[T.A[I]].Kind<>JK_STR)Then Begin
     If(Nm='startswith')or(Nm='endswith')Then Begin
      JqFail(Nm+'() requires string inputs');Exit;
     End;
     IAdd(Out,In_);Continue;
    End;
    S:=JP[In_].S;S2:=JP[T.A[I]].S;
    If Nm='startswith' Then IAdd(Out,MkBool(StartsWith(S,S2)))
    Else If Nm='endswith' Then IAdd(Out,MkBool(EndsWith(S,S2)))
    Else Begin
     If(Nm<>'rtrimstr')and StartsWith(S,S2)Then Delete(S,1,Length(S2));
     If(Nm<>'ltrimstr')and EndsWith(S,S2)Then Delete(S,Length(S)-Length(S2)+1,Length(S2));
     IAdd(Out,MkStr(S));
    End;
   End;
   Exit;
  End;
  If(Nm='split')and(NA=1)Then Begin
   Ev(A,In_,T);
   For I:=0 to T.N-1 do Begin
    If(JP[In_].Kind<>JK_STR)or(JP[T.A[I]].Kind<>JK_STR)Then Begin JqFail('split input and separator must be strings');Exit;End;
    IAdd(Out,BinOp('/',In_,T.A[I]));
   End;
   Exit;
  End;
  If Nm='join' Then Begin
   Ev(A,In_,T);
   For I:=0 to T.N-1 do Begin
    ArrItems(In_,Els);
    S:='';
    For J:=0 to Els.N-1 do Begin
     If J>0 Then S:=S+ToStr(T.A[I]);
     X:=Els.A[J];
     Case TypeOrd(X)of
      0:;
      1,2,3:S:=S+JP[X].S;
      4:S:=S+JP[X].S;
      Else Begin JqFail('Cannot join with '+TypeName(X));Exit;End;
     End;
    End;
    IAdd(Out,MkStr(S));
   End;
   Exit;
  End;
  If(Nm='test')or(Nm='match')or(Nm='capture')or(Nm='scan')or(Nm='splits')or(Nm='sub')or(Nm='gsub')or
    ((Nm='split')and(NA=2))Then Begin
   If JP[In_].Kind<>JK_STR Then Begin JqFail(TypeName(In_)+' ('+Copy(ToStr(In_),1,11)+') cannot be matched, as it is not a string');Exit;End;
   Ev(A,In_,T);
   For I:=0 to T.N-1 do Begin
    Fl:='';
    If(Nm='split')or(Nm='splits')Then Begin
     If NA>=2 Then Begin T2.N:=0;Ev(B,In_,T2);If T2.N>0 Then Fl:=ToStr(T2.A[0]);End;
    End
    Else If(Nm='sub')or(Nm='gsub')Then Begin
     If NA>=3 Then Begin T2.N:=0;Ev(C,In_,T2);If T2.N>0 Then Fl:=ToStr(T2.A[0]);End;
    End
    Else If NA>=2 Then Begin T2.N:=0;Ev(B,In_,T2);If T2.N>0 Then Fl:=ToStr(T2.A[0]);End;
    If Nm='gsub' Then Fl:=Fl+'g';
    If(Nm='scan')or(Nm='splits')or(Nm='split')Then Fl:=Fl+'g';
    S:=ToStr(T.A[I]);
    Els.N:=0;
    RegexMatches(JP[In_].S,S,Fl,Els);
    If JqErrS<>'' Then Exit;
    If Nm='test' Then IAdd(Out,MkBool(Els.N>0))
    Else If Nm='match' Then Begin For J:=0 to Els.N-1 do IAdd(Out,Els.A[J]);End
    Else If Nm='capture' Then Begin
     For J:=0 to Els.N-1 do Begin
      R:=MkObj;
      X:=JGet(Els.A[J],'captures');
      Y:=JP[X].First;
      While Y>=0 do Begin
       If JS(Y,'name')<>'' Then ObjSet(R,JS(Y,'name'),JGet(Y,'string'));
       Y:=JP[Y].Next;
      End;
      IAdd(Out,R);
     End;
    End
    Else If Nm='scan' Then Begin
     For J:=0 to Els.N-1 do Begin
      X:=JGet(Els.A[J],'captures');
      If JP[X].Cnt=0 Then IAdd(Out,JGet(Els.A[J],'string'))
      Else Begin
       R:=MkArr;
       Y:=JP[X].First;
       While Y>=0 do Begin ArrAdd(R,JGet(Y,'string'));Y:=JP[Y].Next;End;
       IAdd(Out,R);
      End;
     End;
    End
    Else If(Nm='splits')or(Nm='split')Then Begin
     R:=MkArr;
     K:=0;
     For J:=0 to Els.N-1 do Begin
      N:=Trunc(NumOf(JGet(Els.A[J],'offset')));
      ArrAdd(R,MkStr(U8Sub(JP[In_].S,K,N)));
      K:=N+Trunc(NumOf(JGet(Els.A[J],'length')));
     End;
     ArrAdd(R,MkStr(U8Sub(JP[In_].S,K,U8Len(JP[In_].S))));
     If Nm='split' Then IAdd(Out,R)
     Else Begin X:=JP[R].First;While X>=0 do Begin IAdd(Out,X);X:=JP[X].Next;End;End;
    End
    Else Begin
     { sub / gsub : le remplacement est evalue avec l'objet des captures }
     S2:='';K:=0;
     For J:=0 to Els.N-1 do Begin
      N:=Trunc(NumOf(JGet(Els.A[J],'offset')));
      S2:=S2+U8Sub(JP[In_].S,K,N);
      R:=MkObj;
      X:=JGet(Els.A[J],'captures');
      Y:=JP[X].First;
      While Y>=0 do Begin
       If JS(Y,'name')<>'' Then ObjSet(R,JS(Y,'name'),JGet(Y,'string'));
       Y:=JP[Y].Next;
      End;
      T2.N:=0;
      Ev(B,R,T2);
      If JqErrS<>'' Then Exit;
      If T2.N>0 Then S2:=S2+ToStr(T2.A[0]);
      K:=N+Trunc(NumOf(JGet(Els.A[J],'length')));
     End;
     S2:=S2+U8Sub(JP[In_].S,K,U8Len(JP[In_].S));
     IAdd(Out,MkStr(S2));
    End;
   End;
   Exit;
  End;
  If(Nm='any')or(Nm='all')Then Begin
   Ok:=Nm='all';
   If NA=1 Then Begin ArrItems(In_,Els);Y:=A;End
   Else Begin Els.N:=0;Ev(A,In_,Els);Y:=B;End;
   For I:=0 to Els.N-1 do Begin
    T.N:=0;
    Ev(Y,Els.A[I],T);
    For J:=0 to T.N-1 do
     If Nm='any' Then Begin If Truthy(T.A[J])Then Ok:=True;End
     Else If not Truthy(T.A[J])Then Ok:=False;
   End;
   IAdd(Out,MkBool(Ok));Exit;
  End;
  If Nm='flatten' Then Begin
   Ev(A,In_,T);
   For I:=0 to T.N-1 do Begin
    If NumOf(T.A[I])<0 Then Begin JqFail('flatten depth must not be negative');Exit;End;
    R:=MkArr;FlattenInto(In_,Trunc(NumOf(T.A[I])),R);IAdd(Out,R);
   End;
   Exit;
  End;
  If Nm='range' Then Begin
   If NA=1 Then Begin
    Ev(A,In_,T);
    For I:=0 to T.N-1 do Begin
     D:=0;
     While D<NumOf(T.A[I])do Begin IAdd(Out,MkNum(D));D:=D+1;If Out.N>1000000 Then Break;End;
    End;
   End
   Else Begin
    Ev(A,In_,T);Els.N:=0;Ev(B,In_,Els);
    For I:=0 to T.N-1 do
     For J:=0 to Els.N-1 do Begin
      D:=NumOf(T.A[I]);
      Keys.N:=0;
      If NA=3 Then Ev(C,In_,Keys);
      If(NA=3)and(Keys.N>0)Then X:=0 Else X:=-1;
      If X=0 Then Begin
       { pas explicite }
       If NumOf(Keys.A[0])>0 Then Begin While D<NumOf(Els.A[J])do Begin IAdd(Out,MkNum(D));D:=D+NumOf(Keys.A[0]);End;End
       Else If NumOf(Keys.A[0])<0 Then Begin While D>NumOf(Els.A[J])do Begin IAdd(Out,MkNum(D));D:=D+NumOf(Keys.A[0]);End;End;
      End
      Else While D<NumOf(Els.A[J])do Begin IAdd(Out,MkNum(D));D:=D+1;If Out.N>1000000 Then Break;End;
     End;
   End;
   Exit;
  End;
  If(Nm='first')or(Nm='last')or(Nm='isempty')Then Begin
   Ev(A,In_,T);
   If Nm='isempty' Then IAdd(Out,MkBool(T.N=0))
   Else If T.N>0 Then Begin
    If Nm='first' Then IAdd(Out,T.A[0]) Else IAdd(Out,T.A[T.N-1]);
   End;
   Exit;
  End;
  If Nm='nth' Then Begin
   If NA=1 Then Begin
    Ev(A,In_,T);
    For I:=0 to T.N-1 do Begin
     K:=Trunc(NumOf(T.A[I]));
     If JP[In_].Kind=JK_ARR Then Begin
      If(K>=0)and(K<JP[In_].Cnt)Then IAdd(Out,JAt(In_,K)) Else IAdd(Out,MkNull);
     End;
    End;
   End
   Else Begin
    Ev(A,In_,T);
    For I:=0 to T.N-1 do Begin
     Els.N:=0;Ev(B,In_,Els);
     K:=Trunc(NumOf(T.A[I]));
     If(K>=0)and(K<Els.N)Then IAdd(Out,Els.A[K]);
    End;
   End;
   Exit;
  End;
  If Nm='limit' Then Begin
   Ev(A,In_,T);
   For I:=0 to T.N-1 do Begin
    Els.N:=0;Ev(B,In_,Els);
    For J:=0 to Els.N-1 do If J<Trunc(NumOf(T.A[I]))Then IAdd(Out,Els.A[J]);
   End;
   Exit;
  End;
  If(Nm='sort_by')or(Nm='group_by')or(Nm='unique_by')or(Nm='min_by')or(Nm='max_by')Then Begin
   If JP[In_].Kind<>JK_ARR Then Begin JqFail('Cannot index '+TypeName(In_)+' with number');Exit;End;
   ArrItems(In_,Els);
   SortKeys(Els,A,Keys);
   If JqErrS<>'' Then Exit;
   If(Nm='min_by')or(Nm='max_by')Then Begin
    If Els.N=0 Then Begin IAdd(Out,MkNull);Exit;End;
    X:=0;
    For I:=1 to Els.N-1 do
     If Nm='min_by' Then Begin If JCmp(Keys.A[I],Keys.A[X])<0 Then X:=I;End
     Else If JCmp(Keys.A[I],Keys.A[X])>=0 Then X:=I;
    IAdd(Out,Els.A[X]);Exit;
   End;
   Idx:=SortedIdx(Els,Keys);
   R:=MkArr;
   If Nm='sort_by' Then Begin
    For I:=0 to Idx.N-1 do ArrAdd(R,Els.A[Idx.A[I]]);
   End
   Else Begin
    Y:=-1;
    For I:=0 to Idx.N-1 do Begin
     If(I=0)or(JCmp(Keys.A[Idx.A[I]],Keys.A[Idx.A[I-1]])<>0)Then Begin
      If Nm='group_by' Then Begin Y:=MkArr;ArrAdd(R,Y);ArrAdd(JAt(R,JP[R].Cnt-1),Els.A[Idx.A[I]]);End
      Else ArrAdd(R,Els.A[Idx.A[I]]);
     End
     Else If Nm='group_by' Then ArrAdd(JP[R].Last,Els.A[Idx.A[I]]);
    End;
   End;
   IAdd(Out,R);Exit;
  End;
  If Nm='unique_by' Then Exit;
  If Nm='with_entries' Then Begin
   Els.N:=0;ToEntries(In_,Els);
   If JqErrS<>'' Then Exit;
   R:=MkArr;
   X:=JP[Els.A[0]].First;
   While X>=0 do Begin
    T.N:=0;
    Ev(A,X,T);
    For J:=0 to T.N-1 do ArrAdd(R,T.A[J]);
    X:=JP[X].Next;
   End;
   FromEntries(R,Out);Exit;
  End;
  If Nm='del' Then Begin
   Els.N:=0;Keys.N:=0;
   PathEval(A,In_,MkArr,Els,Keys);
   If JqErrS<>'' Then Exit;
   IAdd(Out,DelPaths(In_,Keys));Exit;
  End;
  If Nm='path' Then Begin
   Els.N:=0;Keys.N:=0;
   PathEval(A,In_,MkArr,Els,Keys);
   For I:=0 to Keys.N-1 do IAdd(Out,Keys.A[I]);
   Exit;
  End;
  If Nm='getpath' Then Begin
   Ev(A,In_,T);
   For I:=0 to T.N-1 do IAdd(Out,GetAt(In_,T.A[I]));
   Exit;
  End;
  If Nm='setpath' Then Begin
   Ev(A,In_,T);Els.N:=0;Ev(B,In_,Els);
   For I:=0 to T.N-1 do For J:=0 to Els.N-1 do IAdd(Out,SetAt(In_,T.A[I],Els.A[J]));
   Exit;
  End;
  If Nm='delpaths' Then Begin
   Ev(A,In_,T);
   For I:=0 to T.N-1 do Begin
    Keys.N:=0;
    X:=JP[T.A[I]].First;
    While X>=0 do Begin IAdd(Keys,X);X:=JP[X].Next;End;
    IAdd(Out,DelPaths(In_,Keys));
   End;
   Exit;
  End;
  If Nm='paths' Then Begin
   Els.N:=0;Keys.N:=0;
   X:=QNew(Q_REC,'',-1,-1,-1);
   PathEval(X,In_,MkArr,Els,Keys);
   For I:=1 to Keys.N-1 do Begin
    T.N:=0;Ev(A,Els.A[I],T);
    For J:=0 to T.N-1 do If Truthy(T.A[J])Then Begin IAdd(Out,Keys.A[I]);Break;End;
   End;
   Exit;
  End;
  If Nm='error' Then Begin
   Ev(A,In_,T);
   If T.N>0 Then JqFail(ToStr(T.A[0]));
   Exit;
  End;
  If Nm='tostring' Then Begin IAdd(Out,MkStr(ToStr(In_)));Exit;End;
  If(Nm='index')or(Nm='rindex')or(Nm='indices')Then Begin
   Ev(A,In_,T);
   For I:=0 to T.N-1 do Begin
    R:=MkArr;
    If(JP[In_].Kind=JK_STR)and(JP[T.A[I]].Kind=JK_STR)Then Begin
     S:=JP[In_].S;S2:=JP[T.A[I]].S;
     K:=1;
     If S2<>'' Then While K<=Length(S)do Begin
      N:=Pos(S2,Copy(S,K,Length(S)));
      If N=0 Then Break;
      ArrAdd(R,MkNum(U8Len(Copy(S,1,K+N-2))));
      K:=K+N;
     End;
    End
    Else If JP[In_].Kind=JK_ARR Then Begin
     X:=JP[In_].First;K:=0;
     While X>=0 do Begin
      If JP[T.A[I]].Kind=JK_ARR Then Begin
       Ok:=True;Y:=JP[T.A[I]].First;N:=0;
       While Y>=0 do Begin
        If(JAt(In_,K+N)<0)or(JCmp(JAt(In_,K+N),Y)<>0)Then Begin Ok:=False;Break;End;
        Inc(N);Y:=JP[Y].Next;
       End;
       If Ok and(JP[T.A[I]].Cnt>0)Then ArrAdd(R,MkNum(K));
      End
      Else If JCmp(X,T.A[I])=0 Then ArrAdd(R,MkNum(K));
      Inc(K);X:=JP[X].Next;
     End;
    End;
    If Nm='indices' Then IAdd(Out,R)
    Else If JP[R].Cnt=0 Then IAdd(Out,MkNull)
    Else If Nm='index' Then IAdd(Out,JP[R].First) Else IAdd(Out,JP[R].Last);
   End;
   Exit;
  End;
  If Nm='strftime' Then Begin
   Ev(A,In_,T);
   For I:=0 to T.N-1 do Begin
    If JP[In_].Kind<>JK_NUM Then Begin JqFail('strftime/1 requires parsed datetime inputs');Exit;End;
    IAdd(Out,MkStr(StrftimeImpl(ToStr(T.A[I]),Trunc(NumOf(In_)))));
   End;
   Exit;
  End;
  If Nm='splits' Then Exit;
  If Nm='pow' Then Begin
   Ev(A,In_,T);Els.N:=0;Ev(B,In_,Els);
   For I:=0 to T.N-1 do For J:=0 to Els.N-1 do
     IAdd(Out,MkNum(Exp(NumOf(Els.A[J])*Ln(NumOf(T.A[I])))));
   Exit;
  End;
  If Nm='walk' Then Begin
   { applique f aux enfants puis au noeud }
   Els.N:=0;
   Ev(A,In_,T);
   For I:=0 to T.N-1 do IAdd(Out,T.A[I]);
   Exit;
  End;
  If Nm='IN' Then Begin
   Ev(A,In_,T);Ok:=False;
   For I:=0 to T.N-1 do If JCmp(T.A[I],In_)=0 Then Ok:=True;
   IAdd(Out,MkBool(Ok));Exit;
  End;
  If Nm='add' Then Begin
   Ev(A,In_,T);
   R:=MkNull;
   For I:=0 to T.N-1 do Begin R:=BinOp('+',R,T.A[I]);If JqErrS<>'' Then Exit;End;
   IAdd(Out,R);Exit;
  End;
  If(Nm='until')or(Nm='while')or(Nm='repeat')Then Begin
   { until(cond;update) ; while(cond;update) ; repeat(update) limite }
   X:=In_;
   For I:=1 to 100000 do Begin
    T.N:=0;
    If Nm='repeat' Then Begin
     IAdd(Out,X);
     Ev(A,X,T);
     If(T.N=0)or(JqErrS<>'')Then Break;
     X:=T.A[0];
     If I>=10000 Then Break;
     Continue;
    End;
    Ev(A,X,T);
    If T.N=0 Then Break;
    Ok:=Truthy(T.A[0]);
    If Nm='until' Then Begin
     If Ok Then Begin IAdd(Out,X);Break;End;
    End
    Else Begin
     If not Ok Then Break;
     IAdd(Out,X);
    End;
    T.N:=0;
    Ev(B,X,T);
    If(T.N=0)or(JqErrS<>'')Then Break;
    X:=T.A[0];
   End;
   Exit;
  End;
  If Nm='todate' Then Exit;
 End;
 JqFail(Nm+'/'+IStr(NA)+' is not defined');
End;

{ ---------- boucle d'evaluation ---------- }

Function VarLookup(Const Nm:AnsiString):LongInt;
Var
 I:LongInt;
Begin
 If Nm='ENV' Then Begin VarLookup:=EnvNode;Exit;End;
 For I:=VarN-1 downto 0 do If VarName[I]=Nm Then Begin VarLookup:=VarVal[I];Exit;End;
 JqFail('$'+Nm+' is not defined');
 VarLookup:=MkNull;
End;

Procedure Ev(P,In_:LongInt;Var Out:TIList);
Var
 T,T2,T3:TIList;
 I,J,K,R,X,Acc,Sv:LongInt;
 Ok:Boolean;
 Msg:AnsiString;
Begin
 If(JqErrS<>'')or(P<0)Then Exit;
 T.N:=0;T2.N:=0;T3.N:=0;
 Case JqT[P].Kd of
  Q_ID:IAdd(Out,In_);
  Q_REC:RecurseAll(In_,Out);
  Q_LIT:IAdd(Out,MkStr(JqT[P].S));
  Q_NUM:Begin
         R:=JNew(JK_NUM);JP[R].S:=JqT[P].S;IAdd(Out,R);
        End;
  Q_BOOL:IAdd(Out,MkBool(JqT[P].S='true'));
  Q_NULL:IAdd(Out,MkNull);
  Q_FIELD:Begin
           Ev(JqT[P].A,In_,T);
           For I:=0 to T.N-1 do Begin
            If JqErrS<>'' Then Exit;
            If TypeOrd(T.A[I])=0 Then IAdd(Out,MkNull)
            Else If JP[T.A[I]].Kind=JK_OBJ Then Begin
             X:=JGet(T.A[I],JqT[P].S);
             If X<0 Then X:=MkNull;
             IAdd(Out,X);
            End
            Else JqFail('Cannot index '+TypeName(T.A[I])+' with "'+JqT[P].S+'"');
           End;
          End;
  Q_INDEX:Begin
           Ev(JqT[P].A,In_,T);
           T2.N:=0;SetLength(T2.A,0);
           Ev(JqT[P].B,In_,T2);
           For J:=0 to T2.N-1 do
            For I:=0 to T.N-1 do Begin
             If JqErrS<>'' Then Exit;
             X:=IndexOf(T.A[I],T2.A[J]);
             If(X>=0)and(JqErrS='')Then IAdd(Out,X);
            End;
          End;
  Q_SLICE:Begin
           Ev(JqT[P].A,In_,T);
           For I:=0 to T.N-1 do Begin
            If JqErrS<>'' Then Exit;
            T2.N:=0;SetLength(T2.A,0);T3.N:=0;SetLength(T3.A,0);
            If JqT[P].B>=0 Then Ev(JqT[P].B,In_,T2) Else IAdd(T2,-1);
            If JqT[P].C>=0 Then Ev(JqT[P].C,In_,T3) Else IAdd(T3,-1);
            For J:=0 to T2.N-1 do For K:=0 to T3.N-1 do SliceOf(T.A[I],T2.A[J],T3.A[K],Out);
           End;
          End;
  Q_ITER:Begin
          Ev(JqT[P].A,In_,T);
          For I:=0 to T.N-1 do Begin
           If JqErrS<>'' Then Exit;
           If not(JP[T.A[I]].Kind in[JK_ARR,JK_OBJ])Then Begin
            JqFail('Cannot iterate over '+TypeName(T.A[I])+IfThen_(TypeOrd(T.A[I])<>0,' ('+Copy(ToStr(T.A[I]),1,11)+')',''));
            Exit;
           End;
           X:=JP[T.A[I]].First;
           While X>=0 do Begin IAdd(Out,X);X:=JP[X].Next;End;
          End;
         End;
  Q_ARR:Begin
         R:=MkArr;
         If JqT[P].A>=0 Then Begin
          Ev(JqT[P].A,In_,T);
          For I:=0 to T.N-1 do ArrAdd(R,T.A[I]);
         End;
         If JqErrS='' Then IAdd(Out,R);
        End;
  Q_OBJ:Begin
         R:=MkObj;
         ObjBuild(JqT[P].A,In_,R,Out);
        End;
  Q_STR:EvStrParts(JqT[P].A,In_,'',Out);
  Q_FMT:Begin
         If JqT[P].A<0 Then Begin
          Msg:=FmtApply(JqT[P].S,In_);
          If JqErrS='' Then IAdd(Out,MkStr(Msg));
         End
         Else Begin
          Ev(JqT[P].A,In_,T);
          For I:=0 to T.N-1 do Begin
           Msg:=FmtApply(JqT[P].S,T.A[I]);
           If JqErrS='' Then IAdd(Out,MkStr(Msg));
          End;
         End;
        End;
  Q_NEG:Begin
         Ev(JqT[P].A,In_,T);
         For I:=0 to T.N-1 do Begin
          If JP[T.A[I]].Kind<>JK_NUM Then Begin
           JqFail(TypeName(T.A[I])+' ('+Copy(ToStr(T.A[I]),1,11)+') cannot be negated');Exit;
          End;
          IAdd(Out,MkNum(-NumOf(T.A[I])));
         End;
        End;
  Q_PIPE:Begin
          Ev(JqT[P].A,In_,T);
          For I:=0 to T.N-1 do Begin
           If JqErrS<>'' Then Exit;
           Ev(JqT[P].B,T.A[I],Out);
          End;
         End;
  Q_COMMA:Begin
           Ev(JqT[P].A,In_,Out);
           Ev(JqT[P].B,In_,Out);
          End;
  Q_BIN:Begin
         Ev(JqT[P].B,In_,T2);
         Ev(JqT[P].A,In_,T);
         For J:=0 to T2.N-1 do
          For I:=0 to T.N-1 do Begin
           If JqErrS<>'' Then Exit;
           X:=BinOp(JqT[P].S,T.A[I],T2.A[J]);
           If JqErrS='' Then IAdd(Out,X);
          End;
        End;
  Q_AND,Q_OR:Begin
              Ev(JqT[P].A,In_,T);
              For I:=0 to T.N-1 do Begin
               If(JqT[P].Kd=Q_AND)and not Truthy(T.A[I])Then IAdd(Out,MkBool(False))
               Else If(JqT[P].Kd=Q_OR)and Truthy(T.A[I])Then IAdd(Out,MkBool(True))
               Else Begin
                T2.N:=0;
                Ev(JqT[P].B,In_,T2);
                For J:=0 to T2.N-1 do IAdd(Out,MkBool(Truthy(T2.A[J])));
               End;
              End;
             End;
  Q_ALT:Begin
         Ev(JqT[P].A,In_,T);
         If JqErrS<>'' Then JqErrS:='';
         Ok:=False;
         For I:=0 to T.N-1 do If Truthy(T.A[I])Then Begin IAdd(Out,T.A[I]);Ok:=True;End;
         If not Ok Then Ev(JqT[P].B,In_,Out);
        End;
  Q_IF:Begin
        Ev(JqT[P].A,In_,T);
        For I:=0 to T.N-1 do Begin
         If JqErrS<>'' Then Exit;
         If Truthy(T.A[I])Then Ev(JqT[P].B,In_,Out) Else Ev(JqT[P].C,In_,Out);
        End;
       End;
  Q_VAR:IAdd(Out,VarLookup(JqT[P].S));
  Q_AS:Begin
        Ev(JqT[P].A,In_,T);
        For I:=0 to T.N-1 do Begin
         If JqErrS<>'' Then Exit;
         If VarN<128 Then Begin
          VarName[VarN]:=JqT[P].S;VarVal[VarN]:=T.A[I];Inc(VarN);
          Ev(JqT[P].B,In_,Out);
          Dec(VarN);
         End;
        End;
       End;
  Q_REDUCE:Begin
            Ev(JqT[P].B,In_,T2);
            If T2.N=0 Then Acc:=MkNull Else Acc:=T2.A[0];
            Ev(JqT[P].A,In_,T);
            For I:=0 to T.N-1 do Begin
             If JqErrS<>'' Then Exit;
             VarName[VarN]:=JqT[P].S;VarVal[VarN]:=T.A[I];Inc(VarN);
             T3.N:=0;
             Ev(JqT[P].C,Acc,T3);
             Dec(VarN);
             If T3.N>0 Then Acc:=T3.A[T3.N-1] Else Acc:=MkNull;
            End;
            IAdd(Out,Acc);
           End;
  Q_FOREACH:Begin
             Ev(JqT[P].B,In_,T2);
             If T2.N=0 Then Exit;
             Acc:=T2.A[0];
             Ev(JqT[P].A,In_,T);
             For I:=0 to T.N-1 do Begin
              If JqErrS<>'' Then Exit;
              VarName[VarN]:=JqT[P].S;VarVal[VarN]:=T.A[I];Inc(VarN);
              T3.N:=0;
              Ev(JqT[P].C,Acc,T3);
              For J:=0 to T3.N-1 do Begin
               Acc:=T3.A[J];
               If JqT[P].Nx>=0 Then Ev(JqT[P].Nx,Acc,Out) Else IAdd(Out,Acc);
              End;
              Dec(VarN);
             End;
            End;
  Q_TRY:Begin
         Sv:=VarN;
         Ev(JqT[P].A,In_,T);
         For I:=0 to T.N-1 do IAdd(Out,T.A[I]);
         If JqErrS<>'' Then Begin
          Msg:=JqErrS;JqErrS:='';VarN:=Sv;
          If JqT[P].B>=0 Then Ev(JqT[P].B,MkStr(Msg),Out);
         End;
        End;
  Q_ASSIGN:Begin
            T2.N:=0;SetLength(T2.A,0);
            If JqT[P].S='|=' Then IAdd(T2,MkNull) Else Ev(JqT[P].B,In_,T2);
            For J:=0 to T2.N-1 do Begin
             T.N:=0;T3.N:=0;
             PathEval(JqT[P].A,In_,MkArr,T,T3);
             If JqErrS<>'' Then Exit;
             Acc:=In_;
             For I:=0 to T3.N-1 do Begin
              If JqT[P].S='=' Then X:=T2.A[J]
              Else Begin
               X:=GetAt(Acc,T3.A[I]);
               If JqT[P].S='|=' Then Begin
                T.N:=0;
                Ev(JqT[P].B,X,T);
                If T.N=0 Then Continue;
                X:=T.A[0];
               End
               Else Begin
                Msg:=Copy(JqT[P].S,1,Length(JqT[P].S)-1);
                If Msg='//' Then Begin
                 If Truthy(X)Then Continue;
                 X:=T2.A[J];
                End
                Else X:=BinOp(Msg,X,T2.A[J]);
               End;
              End;
              If JqErrS<>'' Then Exit;
              Acc:=SetAt(Acc,T3.A[I],X);
              If JqErrS<>'' Then Exit;
             End;
             IAdd(Out,Acc);
            End;
           End;
  Q_FUNC:EvFunc(P,In_,Out);
 End;
End;

{ execute un programme jq sur un texte JSON ; ecrit les resultats }
Function JqExec(Const Prog,Json:AnsiString;Pretty:Boolean):Boolean;
Var
 Root,In_,I:LongInt;
 Out:TIList;
 B:TBuf;
Begin
 JqExec:=False;
 Root:=JqCompile(Prog);
 If Root<0 Then Begin
  WriteLn(StdErr,'jq: error: ',JqErrS);
  WriteLn(StdErr,'jq: 1 compile error');
  Exit;
 End;
 In_:=JParse(Json);
 If In_<0 Then Begin WriteLn(StdErr,'jq: error: invalid JSON input');Exit;End;
 Out.N:=0;SetLength(Out.A,0);
 VarN:=0;EnvNodeCache:=-1;JqErrS:='';
 Ev(Root,In_,Out);
 For I:=0 to Out.N-1 do Begin
  If JP[Out.A[I]].Kind=JK_STR Then WriteLn(JP[Out.A[I]].S)
  Else If Pretty Then JPrint(Out.A[I])
  Else WriteLn(RawJson(Out.A[I]));
 End;
 If JqErrS<>'' Then Begin
  WriteLn(StdErr,'jq: error (at <stdin>:0): ',JqErrS);
  Exit;
 End;
 JqExec:=True;
End;
{ ------------------------------------------------------------------ }
{ Modeles Go (--template) : sous-ensemble de text/template + fonctions gh }
{ ------------------------------------------------------------------ }

Const
 TN_TEXT=1; TN_ACT=2; TN_IF=3; TN_RANGE=4; TN_WITH=5; TN_BREAK=6; TN_CONT=7;
 TN_PIPE=10; TN_CMD=11; TN_FIELD=12; TN_STR=13; TN_NUM=14; TN_BOOL=15; TN_NIL=16; TN_IDENT=17;
 TN_SUB=18; TN_DOT=19;

Type
 TTn = Record
  Kd:Byte;
  S,S2,S3:AnsiString;
  A,B,C,Nx:LongInt;
  Decl:Boolean;
 End;

Var
 TT:Array of TTn;
 TTN_:LongInt;
 TErr:AnsiString;
 TOutB:TBuf;
 TRows:TSList;
 TVarN:LongInt;
 TVarName:Array[0..63]of AnsiString;
 TVarVal:Array[0..63]of LongInt;
 TBreak,TCont:Boolean;
 TRoot:LongInt;
 { jetons d'une action }
 TkL:TSList;
 TkI:LongInt;

Function TNew(Kd:Byte;Const S:AnsiString):LongInt;
Begin
 If TTN_>=Length(TT)Then SetLength(TT,Length(TT)*2+32);
 TT[TTN_].Kd:=Kd;TT[TTN_].S:=S;TT[TTN_].S2:='';TT[TTN_].S3:='';
 TT[TTN_].A:=-1;TT[TTN_].B:=-1;TT[TTN_].C:=-1;TT[TTN_].Nx:=-1;TT[TTN_].Decl:=False;
 TNew:=TTN_;
 Inc(TTN_);
End;

Procedure TFail(Const M:AnsiString);
Begin
 If TErr='' Then TErr:=M;
End;

{ ---------- analyse des actions ---------- }

{ decoupe le texte d'une action en jetons ; chaque jeton commence par son genre }
Procedure TokAction(Const S:AnsiString);
Var
 I,St:LongInt;
 C:Char;
 T:AnsiString;
Begin
 SClear(TkL);
 I:=1;
 While I<=Length(S)do Begin
  C:=S[I];
  If C in[' ',#9,#10,#13]Then Inc(I)
  Else If C='"' Then Begin
   T:='';Inc(I);
   While(I<=Length(S))and(S[I]<>'"')do Begin
    If(S[I]='\')and(I<Length(S))Then Begin
     Inc(I);
     Case S[I] of
      'n':T:=T+#10;
      't':T:=T+#9;
      'r':T:=T+#13;
      Else T:=T+S[I];
     End;
    End
    Else T:=T+S[I];
    Inc(I);
   End;
   Inc(I);
   SAdd(TkL,'s'+T);
  End
  Else If C='`' Then Begin
   St:=I+1;Inc(I);
   While(I<=Length(S))and(S[I]<>'`')do Inc(I);
   SAdd(TkL,'s'+Copy(S,St,I-St));
   Inc(I);
  End
  Else If C in['(',')','|',',']Then Begin SAdd(TkL,C+'');Inc(I);End
  Else If(C=':')and(I<Length(S))and(S[I+1]='=')Then Begin SAdd(TkL,':=');Inc(I,2);End
  Else If C='=' Then Begin SAdd(TkL,'=');Inc(I);End
  Else If C in['0'..'9']Then Begin
   St:=I;
   While(I<=Length(S))and(S[I]in['0'..'9','.','e','E'])do Inc(I);
   SAdd(TkL,'n'+Copy(S,St,I-St));
  End
  Else If(C='-')and(I<Length(S))and(S[I+1]in['0'..'9'])Then Begin
   St:=I;Inc(I);
   While(I<=Length(S))and(S[I]in['0'..'9','.','e','E'])do Inc(I);
   SAdd(TkL,'n'+Copy(S,St,I-St));
  End
  Else If(C='.')or(C='$')Then Begin
   St:=I;Inc(I);
   While(I<=Length(S))and(S[I]in['a'..'z','A'..'Z','0'..'9','_','.'])do Inc(I);
   If C='.' Then SAdd(TkL,'f'+Copy(S,St,I-St)) Else SAdd(TkL,'v'+Copy(S,St,I-St));
  End
  Else If C in['a'..'z','A'..'Z','_']Then Begin
   St:=I;
   While(I<=Length(S))and(S[I]in['a'..'z','A'..'Z','0'..'9','_'])do Inc(I);
   SAdd(TkL,'i'+Copy(S,St,I-St));
  End
  Else Begin TFail('unexpected '''+C+''' in command');Exit;End;
 End;
End;

Function TPipeline:LongInt;forward;

Function TOperand:LongInt;
Var
 T,K,V:AnsiString;
 N:LongInt;
Begin
 TOperand:=TNew(TN_NIL,'');
 If TkI>=TkL.N Then Begin TFail('missing operand');Exit;End;
 T:=TkL.A[TkI];K:=Copy(T,1,1);V:=Copy(T,2,Length(T));
 Inc(TkI);
 If T='(' Then Begin
  N:=TPipeline;
  If(TkI<TkL.N)and(TkL.A[TkI]=')')Then Inc(TkI) Else TFail('unclosed left paren');
  TOperand:=TNew(TN_SUB,'');
  TT[TOperand].A:=N;
  If(TkI<TkL.N)and(Copy(TkL.A[TkI],1,1)='f')and(Length(TkL.A[TkI])>2)Then Begin
   TT[TOperand].S:=Copy(TkL.A[TkI],3,Length(TkL.A[TkI]));
   Inc(TkI);
  End;
 End
 Else If K='s' Then TOperand:=TNew(TN_STR,V)
 Else If K='n' Then TOperand:=TNew(TN_NUM,V)
 Else If K='f' Then Begin
  If V='.' Then TOperand:=TNew(TN_DOT,'') Else Begin
   TOperand:=TNew(TN_FIELD,Copy(V,2,Length(V)));
  End;
 End
 Else If K='v' Then Begin
  TOperand:=TNew(TN_FIELD,'');
  N:=Pos('.',V);
  If N>0 Then Begin TT[TOperand].S:=Copy(V,N+1,Length(V));TT[TOperand].S2:=Copy(V,1,N-1);End
  Else TT[TOperand].S2:=V;
 End
 Else If K='i' Then Begin
  If V='true' Then TOperand:=TNew(TN_BOOL,'true')
  Else If V='false' Then TOperand:=TNew(TN_BOOL,'false')
  Else If V='nil' Then TOperand:=TNew(TN_NIL,'')
  Else TOperand:=TNew(TN_IDENT,V);
 End
 Else TFail('unexpected '''+T+''' in operand');
End;

Function TCommand:LongInt;
Var
 First,Last,O:LongInt;
Begin
 TCommand:=TNew(TN_CMD,'');
 First:=-1;Last:=-1;
 While(TkI<TkL.N)and(TkL.A[TkI]<>'|')and(TkL.A[TkI]<>')')do Begin
  O:=TOperand;
  If TErr<>'' Then Exit;
  If First<0 Then First:=O Else TT[Last].Nx:=O;
  Last:=O;
 End;
 If First<0 Then TFail('missing value for command');
 TT[TCommand].A:=First;
End;

Function TPipeline:LongInt;
Var
 First,Last,C,P:LongInt;
 Names:AnsiString;
Begin
 P:=TNew(TN_PIPE,'');
 TPipeline:=P;
 { declaration de variables : $x := ... ou $i, $e := ... }
 If(TkI<TkL.N)and(Copy(TkL.A[TkI],1,1)='v')Then Begin
  If(TkI+1<TkL.N)and((TkL.A[TkI+1]=':=')or(TkL.A[TkI+1]='='))Then Begin
   TT[P].S:=Copy(TkL.A[TkI],2,100);TT[P].Decl:=TkL.A[TkI+1]=':=';
   TT[P].S3:='set';
   Inc(TkI,2);
  End
  Else If(TkI+3<TkL.N)and(TkL.A[TkI+1]=',')and(Copy(TkL.A[TkI+2],1,1)='v')and
    (TkL.A[TkI+3]=':=')Then Begin
   TT[P].S:=Copy(TkL.A[TkI],2,100);TT[P].S2:=Copy(TkL.A[TkI+2],2,100);
   TT[P].Decl:=True;TT[P].S3:='set';
   Inc(TkI,4);
  End;
 End;
 First:=-1;Last:=-1;
 Repeat
  C:=TCommand;
  If TErr<>'' Then Exit;
  If First<0 Then First:=C Else TT[Last].Nx:=C;
  Last:=C;
  If(TkI<TkL.N)and(TkL.A[TkI]='|')Then Inc(TkI) Else Break;
 Until False;
 TT[P].A:=First;
End;

Function TParsePipeText(Const S:AnsiString):LongInt;
Begin
 TokAction(S);
 TkI:=0;
 TParsePipeText:=TPipeline;
 If(TErr='')and(TkI<TkL.N)Then TFail('unexpected '''+TkL.A[TkI]+''' in command');
End;

Function TrimLeftWs(Const S:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 I:=1;
 While(I<=Length(S))and(S[I]in[' ',#9,#10,#13])do Inc(I);
 TrimLeftWs:=Copy(S,I,Length(S));
End;

Function TrimRightWs(Const S:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 I:=Length(S);
 While(I>0)and(S[I]in[' ',#9,#10,#13])do Dec(I);
 TrimRightWs:=Copy(S,1,I);
End;

{ analyse le modele en liste de noeuds ; renvoie la tete de liste }
Function TParse(Const Src:AnsiString):LongInt;
Var
 SNode,SHead,STail,SState:Array[0..31]of LongInt;
 SChain:Array[0..31]of Boolean;
 Sp:LongInt;
 Head,Tail:LongInt;
 Pos_,E,N:LongInt;
 Txt,Act,W,Rest:AnsiString;
 TrimNext,Chain:Boolean;
 Procedure Append(Nd:LongInt);
 Begin
  If Head<0 Then Head:=Nd Else TT[Tail].Nx:=Nd;
  Tail:=Nd;
 End;
 Procedure Push(Nd:LongInt;Ch:Boolean);
 Begin
  If Sp<32 Then Begin
   SNode[Sp]:=Nd;SHead[Sp]:=Head;STail[Sp]:=Tail;SState[Sp]:=0;SChain[Sp]:=Ch;
   Inc(Sp);
  End;
  Head:=-1;Tail:=-1;
 End;
Begin
 TTN_:=0;SetLength(TT,0);TErr:='';
 Sp:=0;Head:=-1;Tail:=-1;
 Pos_:=1;TrimNext:=False;
 While Pos_<=Length(Src)do Begin
  E:=Pos('{{',Copy(Src,Pos_,Length(Src)));
  If E=0 Then Begin
   Txt:=Copy(Src,Pos_,Length(Src));
   If TrimNext Then Txt:=TrimLeftWs(Txt);
   If Txt<>'' Then Begin N:=TNew(TN_TEXT,Txt);Append(N);End;
   Break;
  End;
  Txt:=Copy(Src,Pos_,E-1);
  Inc(Pos_,E+1);
  If TrimNext Then Txt:=TrimLeftWs(Txt);
  TrimNext:=False;
  E:=Pos('}}',Copy(Src,Pos_,Length(Src)));
  If E=0 Then Begin TFail('unclosed action');Break;End;
  Act:=Copy(Src,Pos_,E-1);
  Inc(Pos_,E+1);
  If StartsWith(Act,'- ')or StartsWith(Act,'-'#9)or StartsWith(Act,'-'#10)Then Begin
   Txt:=TrimRightWs(Txt);Act:=Copy(Act,2,Length(Act));
  End;
  If EndsWith(Act,' -')or EndsWith(Act,#9'-')or EndsWith(Act,#10'-')Then Begin
   TrimNext:=True;Act:=Copy(Act,1,Length(Act)-1);
  End;
  If Txt<>'' Then Begin N:=TNew(TN_TEXT,Txt);Append(N);End;
  Act:=TrimStr(Act);
  If StartsWith(Act,'/*')Then Continue;
  W:=Act;
  N:=Pos(' ',W);
  If N>0 Then W:=Copy(W,1,N-1);
  Rest:=TrimStr(Copy(Act,Length(W)+1,Length(Act)));
  If(W='if')or(W='range')or(W='with')Then Begin
   If W='if' Then N:=TNew(TN_IF,'') Else If W='range' Then N:=TNew(TN_RANGE,'') Else N:=TNew(TN_WITH,'');
   TT[N].A:=TParsePipeText(Rest);
   Append(N);
   Push(N,False);
  End
  Else If W='break' Then Begin N:=TNew(TN_BREAK,'');Append(N);End
  Else If W='continue' Then Begin N:=TNew(TN_CONT,'');Append(N);End
  Else If W='else' Then Begin
   If Sp=0 Then Begin TFail('unexpected {{else}}');Break;End;
   If SState[Sp-1]<>0 Then Begin TFail('unexpected {{else}}');Break;End;
   TT[SNode[Sp-1]].B:=Head;
   If StartsWith(Rest,'if ')or(Rest='if')Then Begin
    N:=TNew(TN_IF,'');
    TT[N].A:=TParsePipeText(Copy(Rest,3,Length(Rest)));
    TT[SNode[Sp-1]].C:=N;
    SState[Sp-1]:=2;
    Head:=-1;Tail:=-1;
    Push(N,True);
   End
   Else Begin
    SState[Sp-1]:=1;
    Head:=-1;Tail:=-1;
   End;
  End
  Else If W='end' Then Begin
   If Sp=0 Then Begin TFail('unexpected {{end}}');Break;End;
   Repeat
    If Sp=0 Then Break;
    If SState[Sp-1]=0 Then TT[SNode[Sp-1]].B:=Head
    Else If SState[Sp-1]=1 Then TT[SNode[Sp-1]].C:=Head;
    Chain:=SChain[Sp-1];
    Head:=SHead[Sp-1];Tail:=STail[Sp-1];
    Dec(Sp);
   Until not Chain;
  End
  Else Begin
   N:=TNew(TN_ACT,'');
   TT[N].A:=TParsePipeText(Act);
   Append(N);
  End;
  If TErr<>'' Then Break;
 End;
 If(TErr='')and(Sp>0)Then TFail('unexpected EOF');
 TParse:=Head;
End;

{ ---------- evaluation ---------- }

Function NoValue:LongInt;
Begin
 NoValue:=MkNull;
 JP[NoValue].S:='nv';
End;

Function TTruth(N:LongInt):Boolean;
Begin
 TTruth:=False;
 If N<0 Then Exit;
 Case JP[N].Kind of
  JK_NULL:TTruth:=False;
  JK_BOOL:TTruth:=JP[N].S='true';
  JK_NUM:TTruth:=NumOf(N)<>0;
  JK_STR:TTruth:=JP[N].S<>'';
  Else TTruth:=JP[N].Cnt>0;
 End;
End;

Function TPrint(N:LongInt):AnsiString;
Var
 C:LongInt;
 L,K:TSList;
 I:LongInt;
Begin
 If N<0 Then Begin TPrint:='<nil>';Exit;End;
 Case JP[N].Kind of
  JK_NULL:If JP[N].S='nv' Then TPrint:='<no value>' Else TPrint:='<nil>';
  JK_BOOL,JK_NUM:TPrint:=JP[N].S;
  JK_STR:TPrint:=JP[N].S;
  JK_ARR:Begin
          SClear(L);
          C:=JP[N].First;
          While C>=0 do Begin SAdd(L,TPrint(C));C:=JP[C].Next;End;
          TPrint:='['+JoinList(L,' ')+']';
         End;
  Else Begin
   SClear(K);
   C:=JP[N].First;
   While C>=0 do Begin SAdd(K,JP[C].Key);C:=JP[C].Next;End;
   SSort(K);
   SClear(L);
   For I:=0 to K.N-1 do SAdd(L,K.A[I]+':'+TPrint(JGet(N,K.A[I])));
   TPrint:='map['+JoinList(L,' ')+']';
  End;
 End;
End;

Function TFieldGet(Base:LongInt;Const Path:AnsiString):LongInt;
Var
 L:TSList;
 I,V:LongInt;
Begin
 V:=Base;
 SplitStr(Path,'.',L);
 For I:=0 to L.N-1 do Begin
  If L.A[I]='' Then Continue;
  If(V<0)or(JP[V].Kind<>JK_OBJ)Then Begin
   If(V>=0)and(JP[V].Kind=JK_NULL)Then Begin TFieldGet:=NoValue;Exit;End;
   TFail('can''t evaluate field '+L.A[I]);TFieldGet:=NoValue;Exit;
  End;
  V:=JGet(V,L.A[I]);
  If V<0 Then Begin TFieldGet:=NoValue;Exit;End;
 End;
 TFieldGet:=V;
End;

Function TVarGet(Const Nm:AnsiString):LongInt;
Var
 I:LongInt;
Begin
 If Nm='' Then Begin TVarGet:=TRoot;Exit;End;
 For I:=TVarN-1 downto 0 do If TVarName[I]=Nm Then Begin TVarGet:=TVarVal[I];Exit;End;
 TFail('undefined variable: $'+Nm);
 TVarGet:=NoValue;
End;

Procedure TVarSet(Const Nm:AnsiString;V:LongInt;Decl:Boolean);
Var
 I:LongInt;
Begin
 If not Decl Then Begin
  For I:=TVarN-1 downto 0 do If TVarName[I]=Nm Then Begin TVarVal[I]:=V;Exit;End;
 End;
 If TVarN<64 Then Begin TVarName[TVarN]:=Nm;TVarVal[TVarN]:=V;Inc(TVarN);End;
End;

Function TCmpNodes(A,B:LongInt):LongInt;
Begin
 If(JP[A].Kind=JK_NUM)and(JP[B].Kind=JK_NUM)Then Begin
  If NumOf(A)<NumOf(B)Then TCmpNodes:=-1 Else If NumOf(A)>NumOf(B)Then TCmpNodes:=1 Else TCmpNodes:=0;
 End
 Else If JP[A].Kind<>JP[B].Kind Then TCmpNodes:=2
 Else If JP[A].Kind=JK_STR Then Begin
  If JP[A].S<JP[B].S Then TCmpNodes:=-1 Else If JP[A].S>JP[B].S Then TCmpNodes:=1 Else TCmpNodes:=0;
 End
 Else If JP[A].Kind in[JK_ARR,JK_OBJ]Then Begin If JCmp(A,B)=0 Then TCmpNodes:=0 Else TCmpNodes:=2;End
 Else If JP[A].S=JP[B].S Then TCmpNodes:=0 Else TCmpNodes:=2;
End;

Function HexStr_(N:Int64):AnsiString;
Const
 Hx:AnsiString='0123456789abcdef';
Var
 S:AnsiString;
Begin
 If N=0 Then Begin HexStr_:='0';Exit;End;
 S:='';
 While N>0 do Begin S:=Hx[(N and 15)+1]+S;N:=N shr 4;End;
 HexStr_:=S;
End;

{ format printf de Go (sous-ensemble) }
Function GoPrintf(Const Fmt:AnsiString;Const Args:TIList;First:LongInt):AnsiString;
Var
 I,K,W,Prec:LongInt;
 B:TBuf;
 C:Char;
 Left,Zero,Plus:Boolean;
 S:AnsiString;
 A:LongInt;
 D:Double;
Begin
 BufClear(B);
 I:=1;K:=First;
 While I<=Length(Fmt)do Begin
  C:=Fmt[I];
  If C<>'%' Then Begin BufAdd(B,C);Inc(I);Continue;End;
  Inc(I);
  If I>Length(Fmt)Then Begin BufAdd(B,'%!(NOVERB)');Break;End;
  Left:=False;Zero:=False;Plus:=False;W:=0;Prec:=-1;
  While(I<=Length(Fmt))and(Fmt[I]in['-','0','+',' ','#'])do Begin
   If Fmt[I]='-' Then Left:=True;
   If Fmt[I]='0' Then Zero:=True;
   If Fmt[I]='+' Then Plus:=True;
   Inc(I);
  End;
  While(I<=Length(Fmt))and(Fmt[I]in['0'..'9'])do Begin W:=W*10+Ord(Fmt[I])-48;Inc(I);End;
  If(I<=Length(Fmt))and(Fmt[I]='.')Then Begin
   Inc(I);Prec:=0;
   While(I<=Length(Fmt))and(Fmt[I]in['0'..'9'])do Begin Prec:=Prec*10+Ord(Fmt[I])-48;Inc(I);End;
  End;
  C:=Fmt[I];Inc(I);
  If C='%' Then Begin BufAdd(B,'%');Continue;End;
  If K>=Args.N Then Begin BufAdd(B,'%!'+C+'(MISSING)');Continue;End;
  A:=Args.A[K];Inc(K);
  Case C of
   's','v':S:=TPrint(A);
   'd':Begin
        If JP[A].Kind=JK_NUM Then Begin
         S:=IStr(Trunc(NumOf(A)));
         If Plus and(NumOf(A)>=0)Then S:='+'+S;
        End
        Else S:='%!d('+TypeName(A)+'='+TPrint(A)+')';
       End;
   'f','g','e':Begin
        D:=NumOf(A);
        If Prec<0 Then Prec:=6;
        If C='f' Then Str(D:0:Prec,S) Else S:=NumStr(D);
       End;
   't':S:=TPrint(A);
   'q':S:='"'+ReplaceAll(ReplaceAll(TPrint(A),'\','\\'),'"','\"')+'"';
   'x':Begin
        If JP[A].Kind=JK_NUM Then S:=LoStr(HexStr_(Trunc(NumOf(A)))) Else S:=TPrint(A);
       End;
   Else S:='%!'+C+'('+TPrint(A)+')';
  End;
  If(C='s')and(Prec>=0)and(Length(S)>Prec)Then S:=Copy(S,1,Prec);
  If DispLen(S)<W Then Begin
   If Left Then S:=S+StringOfChar(' ',W-DispLen(S))
   Else If Zero Then S:=StringOfChar('0',W-DispLen(S))+S
   Else S:=StringOfChar(' ',W-DispLen(S))+S;
  End;
  BufAdd(B,S);
 End;
 GoPrintf:=BufStr(B);
End;

{ format de date Go -> texte }
Function GoTimeFmt(Const Lay:AnsiString;E:Int64):AnsiString;
Const
 Mon:Array[1..12]of AnsiString=('January','February','March','April','May','June','July','August',
   'September','October','November','December');
Var
 T,R:AnsiString;
 Mo:LongInt;
Begin
 T:=StampToStr(E);
 Mo:=ToInt(Copy(T,6,2),1);
 R:=Lay;
 R:=ReplaceAll(R,'2006','@Y@');
 R:=ReplaceAll(R,'January','@MN@');
 R:=ReplaceAll(R,'Jan','@MS@');
 R:=ReplaceAll(R,'Monday','@WN@');
 R:=ReplaceAll(R,'Mon','@WS@');
 R:=ReplaceAll(R,'01','@m@');
 R:=ReplaceAll(R,'02','@d@');
 R:=ReplaceAll(R,'15','@H@');
 R:=ReplaceAll(R,'04','@M@');
 R:=ReplaceAll(R,'05','@S@');
 R:=ReplaceAll(R,'MST','UTC');
 R:=ReplaceAll(R,'Z07:00','Z');
 R:=ReplaceAll(R,'@Y@',Copy(T,1,4));
 R:=ReplaceAll(R,'@MN@',Mon[Mo]);
 R:=ReplaceAll(R,'@MS@',Copy(Mon[Mo],1,3));
 R:=ReplaceAll(R,'@WN@',StrftimeImpl('%A',E));
 R:=ReplaceAll(R,'@WS@',StrftimeImpl('%a',E));
 R:=ReplaceAll(R,'@m@',Copy(T,6,2));
 R:=ReplaceAll(R,'@d@',Copy(T,9,2));
 R:=ReplaceAll(R,'@H@',Copy(T,12,2));
 R:=ReplaceAll(R,'@M@',Copy(T,15,2));
 R:=ReplaceAll(R,'@S@',Copy(T,18,2));
 GoTimeFmt:=R;
End;

Function TableText:AnsiString;
Var
 W:Array[0..23]of LongInt;
 I,J,Cols:LongInt;
 Cell:TSList;
 B:TBuf;
 Line:AnsiString;
 Rows:Array of TSList;
Begin
 BufClear(B);
 If not OutTTY Then Begin
  For I:=0 to TRows.N-1 do BufAdd(B,TRows.A[I]+#10);
 End
 Else Begin
  Cols:=0;
  SetLength(Rows,TRows.N);
  For I:=0 to TRows.N-1 do Begin
   SplitStr(TRows.A[I],#9,Rows[I]);
   If Rows[I].N>Cols Then Cols:=Rows[I].N;
  End;
  If Cols>24 Then Cols:=24;
  For I:=0 to Cols-1 do W[I]:=0;
  For I:=0 to TRows.N-1 do
   For J:=0 to Rows[I].N-1 do If(J<Cols)and(DispLen(Rows[I].A[J])>W[J])Then W[J]:=DispLen(Rows[I].A[J]);
  For I:=0 to TRows.N-1 do Begin
   Line:='';
   For J:=0 to Rows[I].N-1 do Begin
    If J<Cols-1 Then Line:=Line+PadD(Rows[I].A[J],W[J])+'  ' Else Line:=Line+Rows[I].A[J];
   End;
   BufAdd(B,TrimRight_(Line)+#10);
  End;
 End;
 SClear(TRows);
 TableText:=BufStr(B);
End;

Function TCall(Const Nm:AnsiString;Const Args:TIList):LongInt;
Var
 Sl_,I,K,R:LongInt;
 S,S2:AnsiString;
 L:TSList;
 Ok:Boolean;
 C:LongInt;
 Function Arg(I:LongInt):LongInt;
 Begin
  If I<Args.N Then Arg:=Args.A[I] Else Begin TFail('wrong number of args for '+Nm);Arg:=NoValue;End;
 End;
Begin
 TCall:=MkNull;
 If(Nm='and')Then Begin
  R:=Arg(0);
  For I:=0 to Args.N-1 do Begin R:=Args.A[I];If not TTruth(R)Then Break;End;
  TCall:=R;Exit;
 End;
 If Nm='or' Then Begin
  R:=Arg(0);
  For I:=0 to Args.N-1 do Begin R:=Args.A[I];If TTruth(R)Then Break;End;
  TCall:=R;Exit;
 End;
 If Nm='not' Then Begin TCall:=MkBool(not TTruth(Arg(0)));Exit;End;
 If(Nm='eq')or(Nm='ne')Then Begin
  Ok:=False;
  For I:=1 to Args.N-1 do If TCmpNodes(Arg(0),Args.A[I])=0 Then Ok:=True;
  If Nm='ne' Then Ok:=TCmpNodes(Arg(0),Arg(1))<>0;
  TCall:=MkBool(Ok);Exit;
 End;
 If(Nm='lt')or(Nm='le')or(Nm='gt')or(Nm='ge')Then Begin
  K:=TCmpNodes(Arg(0),Arg(1));
  If K=2 Then Begin TFail('incompatible types for comparison');Exit;End;
  If Nm='lt' Then Ok:=K<0 Else If Nm='le' Then Ok:=K<=0 Else If Nm='gt' Then Ok:=K>0 Else Ok:=K>=0;
  TCall:=MkBool(Ok);Exit;
 End;
 If Nm='len' Then Begin
  R:=Arg(0);
  If JP[R].Kind=JK_STR Then TCall:=MkNum(U8Len(JP[R].S))
  Else If JP[R].Kind in[JK_ARR,JK_OBJ]Then TCall:=MkNum(JP[R].Cnt)
  Else TFail('len of type '+TypeName(R));
  Exit;
 End;
 If Nm='index' Then Begin
  R:=Arg(0);
  For I:=1 to Args.N-1 do Begin
   If JP[R].Kind=JK_ARR Then Begin
    K:=Trunc(NumOf(Args.A[I]));
    If(K<0)or(K>=JP[R].Cnt)Then Begin TFail('error calling index: index out of range: '+IStr(K));Exit;End;
    R:=JAt(R,K);
   End
   Else If JP[R].Kind=JK_OBJ Then Begin
    R:=JGet(R,TPrint(Args.A[I]));
    If R<0 Then R:=NoValue;
   End
   Else Begin TFail('can''t index item of type '+TypeName(R));Exit;End;
  End;
  TCall:=R;Exit;
 End;
 If Nm='slice' Then Begin
  R:=Arg(0);
  K:=Trunc(NumOf(Arg(1)));
  If Args.N>2 Then I:=Trunc(NumOf(Args.A[2])) Else I:=-1;
  If JP[R].Kind=JK_STR Then Begin
   If I<0 Then I:=U8Len(JP[R].S);
   TCall:=MkStr(U8Sub(JP[R].S,K,I));
  End
  Else Begin
   If I<0 Then I:=JP[R].Cnt;
   C:=MkArr;
   For Sl_:=K to I-1 do ArrAdd(C,JAt(R,Sl_));
   TCall:=C;
  End;
  Exit;
 End;
 If(Nm='print')or(Nm='println')Then Begin
  S:='';
  For I:=0 to Args.N-1 do Begin
   If(I>0)and((Nm='println')or((JP[Args.A[I]].Kind<>JK_STR)and(JP[Args.A[I-1]].Kind<>JK_STR)))Then S:=S+' ';
   S:=S+TPrint(Args.A[I]);
  End;
  If Nm='println' Then S:=S+#10;
  TCall:=MkStr(S);Exit;
 End;
 If Nm='printf' Then Begin TCall:=MkStr(GoPrintf(TPrint(Arg(0)),Args,1));Exit;End;
 If Nm='html' Then Begin TCall:=MkStr(FmtApply('html',MkStr(TPrint(Arg(0)))));Exit;End;
 If Nm='urlquery' Then Begin TCall:=MkStr(UrlEnc(TPrint(Arg(0)),False));Exit;End;
 If Nm='join' Then Begin
  R:=Arg(1);S:='';
  C:=JP[R].First;K:=0;
  While C>=0 do Begin
   If K>0 Then S:=S+TPrint(Arg(0));
   S:=S+TPrint(C);
   Inc(K);C:=JP[C].Next;
  End;
  TCall:=MkStr(S);Exit;
 End;
 If Nm='pluck' Then Begin
  R:=MkArr;
  C:=JP[Arg(1)].First;
  While C>=0 do Begin
   If JGet(C,TPrint(Arg(0)))>=0 Then ArrAdd(R,JGet(C,TPrint(Arg(0))));
   C:=JP[C].Next;
  End;
  TCall:=R;Exit;
 End;
 If Nm='truncate' Then Begin
  K:=Trunc(NumOf(Arg(0)));
  S:=TPrint(Arg(1));
  If DispLen(S)>K Then S:=U8Sub(S,0,K);
  TCall:=MkStr(S);Exit;
 End;
 If Nm='timeago' Then Begin
  TCall:=MkStr(FuzzyAgo(NowEpoch-IsoToEpoch(TPrint(Arg(0)))));Exit;
 End;
 If Nm='timefmt' Then Begin
  TCall:=MkStr(GoTimeFmt(TPrint(Arg(0)),IsoToEpoch(TPrint(Arg(1)))));Exit;
 End;
 If(Nm='color')or(Nm='autocolor')Then Begin TCall:=MkStr(TPrint(Arg(1)));Exit;End;
 If Nm='hyperlink' Then Begin TCall:=MkStr(TPrint(Arg(1)));Exit;End;
 If Nm='tablerow' Then Begin
  SClear(L);
  For I:=0 to Args.N-1 do SAdd(L,TPrint(Args.A[I]));
  SAdd(TRows,JoinList(L,#9));
  TCall:=MkStr('');Exit;
 End;
 If Nm='tablerender' Then Begin TCall:=MkStr(TableText);Exit;End;
 If Nm='contains' Then Begin TCall:=MkBool(Pos(TPrint(Arg(1)),TPrint(Arg(0)))>0);Exit;End;
 If Nm='hasPrefix' Then Begin TCall:=MkBool(StartsWith(TPrint(Arg(0)),TPrint(Arg(1))));Exit;End;
 If Nm='hasSuffix' Then Begin TCall:=MkBool(EndsWith(TPrint(Arg(0)),TPrint(Arg(1))));Exit;End;
 If Nm='regexReplaceAll' Then Begin
  S:=TPrint(Arg(2));
  If not RxCompile(TPrint(Arg(0)),False,False)Then Begin TFail('invalid regexp');Exit;End;
  S2:='';K:=1;
  While K<=Length(S)+1 do Begin
   If not RxSearch(S,K)Then Break;
   S2:=S2+Copy(S,K,RxCap[0]-K)+TPrint(Arg(1));
   If RxCap[1]=RxCap[0]Then Begin S2:=S2+Copy(S,RxCap[0],1);K:=RxCap[0]+1;End Else K:=RxCap[1];
  End;
  S2:=S2+Copy(S,K,Length(S));
  TCall:=MkStr(S2);Exit;
 End;
 TFail('function "'+Nm+'" not defined');
End;

Function StrToDouble_(Const S:AnsiString):Double;
Var
 D:Double;
 C:LongInt;
Begin
 Val(S,D,C);
 If C<>0 Then D:=0;
 StrToDouble_:=D;
End;

Function TEvalPipe(P,Dot:LongInt;NoSet:Boolean):LongInt;forward;

Function TOperandVal(O,Dot:LongInt):LongInt;
Var
 V:LongInt;
 NoArgs:TIList;
Begin
 TOperandVal:=NoValue;
 Case TT[O].Kd of
  TN_DOT:TOperandVal:=Dot;
  TN_FIELD:Begin
            If TT[O].S2='' Then TOperandVal:=TFieldGet(Dot,TT[O].S)
            Else Begin
             V:=TVarGet(TT[O].S2);
             If TT[O].S='' Then TOperandVal:=V Else TOperandVal:=TFieldGet(V,TT[O].S);
            End;
           End;
  TN_STR:TOperandVal:=MkStr(TT[O].S);
  TN_NUM:TOperandVal:=MkNum(StrToDouble_(TT[O].S));
  TN_BOOL:TOperandVal:=MkBool(TT[O].S='true');
  TN_NIL:TOperandVal:=MkNull;
  TN_SUB:Begin
          TOperandVal:=TEvalPipe(TT[O].A,Dot,True);
          If TT[O].S<>'' Then TOperandVal:=TFieldGet(TOperandVal,TT[O].S);
         End;
  TN_IDENT:Begin NoArgs.N:=0;TOperandVal:=TCall(TT[O].S,NoArgs);End;
 End;
End;

Function TEvalCmd(C,Dot,Piped:LongInt):LongInt;
Var
 O:LongInt;
 Args:TIList;
Begin
 O:=TT[C].A;
 If TT[O].Kd=TN_IDENT Then Begin
  Args.N:=0;
  O:=TT[O].Nx;
  While O>=0 do Begin
   IAdd(Args,TOperandVal(O,Dot));
   O:=TT[O].Nx;
  End;
  If Piped>=0 Then IAdd(Args,Piped);
  If TErr<>'' Then Begin TEvalCmd:=NoValue;Exit;End;
  TEvalCmd:=TCall(TT[TT[C].A].S,Args);
 End
 Else TEvalCmd:=TOperandVal(O,Dot);
End;

Function TEvalPipe(P,Dot:LongInt;NoSet:Boolean):LongInt;
Var
 C,V:LongInt;
Begin
 V:=-1;
 C:=TT[P].A;
 While(C>=0)and(TErr='')do Begin
  V:=TEvalCmd(C,Dot,V);
  C:=TT[C].Nx;
 End;
 If V<0 Then V:=NoValue;
 If(not NoSet)and(TT[P].S3='set')and(TT[P].S<>'')Then TVarSet(TT[P].S,V,TT[P].Decl);
 TEvalPipe:=V;
End;

Procedure TExec(Head,Dot:LongInt);
Var
 N,V,C,K,Sv:LongInt;
 Keys:TSList;
 I:LongInt;
 Procedure RangeBody(Elem:LongInt;Key:LongInt);
 Begin
  Sv:=TVarN;
  If TT[TT[N].A].S3='set' Then Begin
   If TT[TT[N].A].S2<>'' Then Begin
    TVarSet(TT[TT[N].A].S,Key,True);TVarSet(TT[TT[N].A].S2,Elem,True);
   End
   Else TVarSet(TT[TT[N].A].S,Elem,True);
  End;
  TExec(TT[N].B,Elem);
  TVarN:=Sv;
 End;
Begin
 N:=Head;
 While(N>=0)and(TErr='')do Begin
  Case TT[N].Kd of
   TN_TEXT:BufAdd(TOutB,TT[N].S);
   TN_ACT:Begin
           V:=TEvalPipe(TT[N].A,Dot,False);
           If TT[TT[N].A].S3<>'set' Then BufAdd(TOutB,TPrint(V));
          End;
   TN_IF:Begin
          V:=TEvalPipe(TT[N].A,Dot,True);
          If TTruth(V)Then TExec(TT[N].B,Dot) Else TExec(TT[N].C,Dot);
         End;
   TN_WITH:Begin
            V:=TEvalPipe(TT[N].A,Dot,True);
            If TTruth(V)Then TExec(TT[N].B,V) Else TExec(TT[N].C,Dot);
           End;
   TN_RANGE:Begin
             V:=TEvalPipe(TT[N].A,Dot,True);
             If not TTruth(V)Then TExec(TT[N].C,Dot)
             Else If JP[V].Kind=JK_ARR Then Begin
              C:=JP[V].First;K:=0;
              While(C>=0)and(TErr='')do Begin
               TBreak:=False;TCont:=False;
               RangeBody(C,MkNum(K));
               If TBreak Then Break;
               Inc(K);C:=JP[C].Next;
              End;
              TBreak:=False;TCont:=False;
             End
             Else If JP[V].Kind=JK_OBJ Then Begin
              SClear(Keys);
              C:=JP[V].First;
              While C>=0 do Begin SAdd(Keys,JP[C].Key);C:=JP[C].Next;End;
              SSort(Keys);
              For I:=0 to Keys.N-1 do Begin
               TBreak:=False;TCont:=False;
               RangeBody(JGet(V,Keys.A[I]),MkStr(Keys.A[I]));
               If TBreak Then Break;
              End;
              TBreak:=False;TCont:=False;
             End
             Else TFail('range can''t iterate over '+TPrint(V));
            End;
   TN_BREAK:Begin TBreak:=True;Exit;End;
   TN_CONT:Begin TCont:=True;Exit;End;
  End;
  If TBreak or TCont Then Exit;
  N:=TT[N].Nx;
 End;
End;

{ applique un modele Go a un texte JSON ; renvoie False en cas d'erreur }
Function TmplExec(Const Tmpl,Json:AnsiString):Boolean;
Var
 Head,Root:LongInt;
Begin
 TmplExec:=False;
 Root:=JParse(Json);
 If Root<0 Then Begin WriteLn(StdErr,'invalid JSON input');Exit;End;
 Head:=TParse(Tmpl);
 If TErr<>'' Then Begin WriteLn(StdErr,'template: ',TErr);Exit;End;
 BufClear(TOutB);SClear(TRows);
 TVarN:=0;TRoot:=Root;TBreak:=False;TCont:=False;
 TExec(Head,Root);
 If TErr<>'' Then Begin WriteLn(StdErr,'template: ',TErr);Exit;End;
 If TOutB.N>0 Then Write(BufStr(TOutB));
 TmplExec:=True;
End;
{ ------------------------------------------------------------------ }
{ Fonctions communes aux commandes                                    }
{ ------------------------------------------------------------------ }

{ sortie JSON : --jq, --template ou JSON brut }
Procedure EmitJson(Const J:AnsiString);
Var
 N:LongInt;
Begin
 If JqExpr<>'' Then Begin
  If not JqExec(JqExpr,J,OutTTY)Then Halt(1);
 End
 Else If TmplText<>'' Then Begin
  If not TmplExec(TmplText,J)Then Halt(1);
 End
 Else If OutTTY Then Begin
  N:=JParse(J);
  If N>=0 Then JPrint(N) Else WriteLn(J);
 End
 Else WriteLn(J);
End;

Function InteractiveOk:Boolean;
Begin
 InteractiveOk:=InTTY and OutTTY and(CfgGet('prompt','')<>'disabled')and(GetEnv('GH_PROMPT_DISABLED')='');
End;

Function AskLine(Const Q_,Def:AnsiString):AnsiString;
Var
 S:AnsiString;
Begin
 Write(StdErr,'? ',Q_);
 If Def<>'' Then Write(StdErr,' (',Def,')');
 Write(StdErr,' ');
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

{ hote cible d'une commande qui n'est pas liee a un depot }
Procedure InitHostOpt;
Var
 H:AnsiString;
Begin
 H:=OptGet('hostname');
 If H='' Then H:=DefaultHost;
 ApiHost:=H;
End;

{ resout le depot et selectionne son hote }
Procedure NeedRepo;
Begin
 ResolveRepo(True);
 ApiHost:=RepoHost;
End;

Function RepoApi(Const Path:AnsiString):AnsiString;
Begin
 RepoApi:='/repos/'+RepoOwner+'/'+RepoName+Path;
End;

Function RepoWebUrl:AnsiString;
Begin
 RepoWebUrl:=WebBaseOf(RepoHost)+'/'+RepoOwner+'/'+RepoName;
End;

{ ouvre ou affiche une URL pour --web }
Procedure OpenWeb(Const Url:AnsiString);
Begin
 If ErrTTY Then WriteLn(StdErr,'Opening ',Copy(Url,Pos('://',Url)+3,Length(Url)),' in your browser.');
 OpenBrowser(Url);
End;

{ numero d'un ticket ou d'une pull request : 12, #12 ou URL }
Function ParseNumArg(Const S_,Kind:AnsiString):LongInt;
Var
 S,H,O,N:AnsiString;
 L:TSList;
 I,V:LongInt;
Begin
 S:=TrimStr(S_);
 If S='' Then Die('invalid '+Kind+' number');
 If S[1]='#' Then Delete(S,1,1);
 V:=ToInt(S,-1);
 If V>0 Then Begin ParseNumArg:=V;Exit;End;
 If(Pos('://',S)>0)Then Begin
  SplitStr(S,'/',L);
  If L.N>=7 Then Begin
   RepoHost:=L.A[2];RepoOwner:=L.A[3];RepoName:=L.A[4];RepoResolved:=True;
   ApiHost:=RepoHost;
   V:=ToInt(L.A[6],-1);
   If V>0 Then Begin ParseNumArg:=V;Exit;End;
  End;
 End;
 Die('invalid '+Kind+' format: '+S_);
End;

{ corps du message : --body, --body-file ('-' = stdin) ; Given=False si aucun }
Function BodyOpt(Var Given:Boolean):AnsiString;
Var
 F,S:AnsiString;
Begin
 Given:=False;BodyOpt:='';
 If OptHas('body')Then Begin Given:=True;BodyOpt:=OptGet('body');End;
 If OptHas('body-file')Then Begin
  Given:=True;
  F:=OptGet('body-file');
  If F='-' Then BodyOpt:=ReplaceAll(ReadStdin,#13,'')
  Else If ReadAll(F,S)Then BodyOpt:=ReplaceAll(S,#13,'')
  Else Die('open '+F+': no such file or directory');
 End;
End;

{ lit plusieurs lignes jusqu'a une ligne vide }
Function AskBody(Const Q_:AnsiString):AnsiString;
Var
 L:AnsiString;
 B:TBuf;
Begin
 WriteLn(StdErr,'? ',Q_,' (finish with an empty line)');
 BufClear(B);
 Repeat
  L:=ReadLine_;
  If(L='')Then Break;
  BufAdd(B,L+#10);
 Until Eof(Input);
 AskBody:=Copy(BufStr(B),1,B.N-1);
End;

Function NowIso:AnsiString;
Begin
 NowIso:=EpochToIso(NowEpoch);
End;

{ date seule AAAA-MM-JJ }
Function DateOnly(Const S:AnsiString):AnsiString;
Begin
 DateOnly:=Copy(S,1,10);
End;

Function FirstLine(Const S:AnsiString):AnsiString;
Var
 P:LongInt;
Begin
 P:=Pos(#10,S);
 If P=0 Then FirstLine:=TrimStr(S) Else FirstLine:=TrimStr(Copy(S,1,P-1));
End;

{ texte de repli pour les valeurs vides }
Function OrDash(Const S:AnsiString):AnsiString;
Begin
 If S='' Then OrDash:='-' Else OrDash:=S;
End;

{ liste d'etiquettes "a, b" depuis un tableau JSON de noeuds portant name }
Function NamesOf(A:LongInt;Const Key:AnsiString):AnsiString;
Var
 C:LongInt;
 L:TSList;
Begin
 SClear(L);
 If A>=0 Then Begin
  C:=JP[A].First;
  While C>=0 do Begin
   If Key='' Then SAdd(L,JTxt(C)) Else SAdd(L,JS(C,Key));
   C:=JP[C].Next;
  End;
 End;
 NamesOf:=JoinList(L,', ');
End;

{ affiche la reponse d'une requete JSON avec les champs de Spec (--json) ; Hook optionnel }
Procedure EmitItems(Const Items:TIList;Const Spec:AnsiString;Hook:TFieldHook);
Var
 L:TSList;
 I:LongInt;
Begin
 SClear(L);
 For I:=0 to Items.N-1 do SAdd(L,ShapeObj(Items.A[I],Spec,Hook));
 EmitJson('['+JoinList(L,',')+']');
End;

Procedure EmitItem(Node:LongInt;Const Spec:AnsiString;Hook:TFieldHook);
Begin
 EmitJson(ShapeObj(Node,Spec,Hook));
End;

{ ajoute l'etat a une requete de liste GitHub : open|closed|all }
Function StateParam(Const S:AnsiString):AnsiString;
Var
 T:AnsiString;
Begin
 T:=LoStr(S);
 If(T='open')or(T='closed')or(T='all')Then StateParam:=T
 Else Begin
  UsageErr('invalid argument "'+S+'" for "-s, --state" flag: valid values are {open|closed|all}');
  StateParam:='open';
 End;
End;

{ encode un segment de chemin d'URL }
Function PathEnc(Const S:AnsiString):AnsiString;
Begin
 PathEnc:=UrlEnc(S,False);
End;

{ ajoute a Fields des assignees/labels depuis les options multiples }
Procedure AddListField(Var L:TSList;Const Key:AnsiString;Const Items:TSList);
Begin
 FR(L,Key,StrArr(Items));
End;

{ remplace @me par le nom d'utilisateur courant }
Var
 MeCache:AnsiString;

Function CurrentUser:AnsiString;
Var
 J:LongInt;
Begin
 If MeCache<>'' Then Begin CurrentUser:=MeCache;Exit;End;
 J:=ApiJ('GET','/user','');
 MeCache:=JS(J,'login');
 CurrentUser:=MeCache;
End;

Function ResolveMe(Const S:AnsiString):AnsiString;
Begin
 If S='@me' Then ResolveMe:=CurrentUser Else ResolveMe:=S;
End;

{ nom de l'hote en format affichable }
Function ShowHost(Const H:AnsiString):AnsiString;
Begin
 ShowHost:=GitHostName(H);
End;
{ ------------------------------------------------------------------ }
{ gh auth, config, alias                                              }
{ ------------------------------------------------------------------ }

{$IFDEF WINDOWS}
Procedure Sleep(Ms:LongWord);stdcall;external 'kernel32.dll' name 'Sleep';
{$ENDIF}

Procedure SleepSec(N:LongInt);
Begin
 {$IFDEF WINDOWS}
 Sleep(N*1000);
 {$ELSE}
 RunShell('sleep '+IStr(N));
 {$ENDIF}
End;

Function MaskTok(Const T:AnsiString):AnsiString;
Var
 P:LongInt;
Begin
 P:=Pos('_',T);
 If(P>0)and(P<=4)Then MaskTok:=Copy(T,1,P)+StringOfChar('*',Length(T)-P)
 Else MaskTok:=StringOfChar('*',Length(T));
End;

{ requete HTTP brute sur l'hote web (flux d'appareil, formulaires) }
Procedure WebForm(Var R:THttpReq;Const Host,Path,Body:AnsiString);
Begin
 ReqInit(R,'POST',WebBaseOf(Host)+Path,'');
 R.BodyStr:=Body;
 R.Headers:='Accept: application/json'#13#10'Content-Type: application/x-www-form-urlencoded'#13#10;
 HttpDo(R);
 If R.Err<>'' Then Die(R.Err);
End;

{ valide un jeton et renvoie l'utilisateur ; Scopes recoit X-OAuth-Scopes }
Function CheckToken(Const Host,Tok:AnsiString;Var Scopes:AnsiString;Var Valid:Boolean):AnsiString;
Var
 R:THttpReq;
 J:LongInt;
Begin
 CheckToken:='';Scopes:='';Valid:=False;
 ReqInit(R,'GET',ApiBaseOf(Host)+'/user',Tok);
 HttpDo(R);
 If(R.Err<>'')or(R.Status<>200)Then Exit;
 Scopes:=HeaderGet(R.RespHeaders,'x-oauth-scopes');
 J:=JParse(R.RespBody);
 CheckToken:=JS(J,'login');
 Valid:=True;
End;

Procedure StoreLogin(Const Host,User,Tok,Proto:AnsiString);
Var
 Active:Boolean;
Begin
 YSet(HostsY,Host+'|users|'+User+'|oauth_token',Tok);
 YSet(HostsY,Host+'|oauth_token',Tok);
 YSet(HostsY,Host+'|user',User);
 If Proto<>'' Then YSet(HostsY,Host+'|git_protocol',Proto);
 SaveHosts;
End;

Function HasScope(Const Scopes,S:AnsiString):Boolean;
Var
 L:TSList;
 I:LongInt;
Begin
 HasScope:=False;
 SplitStr(ReplaceAll(Scopes,' ',''),',',L);
 For I:=0 to L.N-1 do If L.A[I]=S Then HasScope:=True;
End;

Procedure CmdAuthLogin;
Var
 Host,Tok,User,Scopes,Proto,Sc:AnsiString;
 Valid,Web:Boolean;
 R:THttpReq;
 J,Interval,I:LongInt;
 Dev,UCode,Uri:AnsiString;
 Sl:TSList;
 Opts:TSList;
Begin
 CmdBegin('auth login','');
 Opt('clipboard','c','','Copy one-time OAuth device code to clipboard@@Copie le code '+#133+' usage unique dans le presse-papiers');
 Opt('git-protocol','p','string','The protocol to use for git operations on this host: {ssh|https}@@Le protocole utilis'+#130+' pour les op'+#130+'rations git sur cet h'+#147+'te : {ssh|https}');
 Opt('hostname','h','string','The hostname of the GitHub instance to authenticate with@@Le nom d''h'+#147+'te de l''instance GitHub');
 Opt('insecure-storage','','','Save credentials in plain text instead of credential store@@Enregistre les identifiants en clair');
 Opt('scopes','s','*strings','Additional authentication scopes to request@@Port'+#130+'es d''authentification suppl'+#130+'mentaires '+#133+' demander');
 Opt('skip-ssh-key','','','Skip generate/upload SSH key prompt@@Ne propose pas de g'+#130+'n'+#130+'rer ou t'+#130+'l'+#130+'verser une cl'+#130+' SSH');
 Opt('web','w','','Open a browser to authenticate@@Ouvre un navigateur pour s''authentifier');
 Opt('with-token','','','Read token from standard input@@Lit le jeton sur l''entr'+#130+'e standard');
 CmdLong('Authenticate with a GitHub host.@@S''authentifie aupr'+#138+'s d''un h'+#147+'te GitHub.');
 CmdExample('# authenticate against github.com by reading the token from a file');
 CmdExample('$ gh auth login --with-token < mytoken.txt');
 CmdExample('# authenticate with a specific GitHub instance');
 CmdExample('$ gh auth login --hostname enterprise.internal');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 Host:=OptGet('hostname');
 Proto:=LoStr(OptGet('git-protocol'));
 If(Proto<>'')and(Proto<>'ssh')and(Proto<>'https')Then UsageErr('invalid value for --git-protocol');
 If Host='' Then Begin
  If InteractiveOk and not OptHas('with-token')Then Begin
   SClear(Opts);SAdd(Opts,'GitHub.com');SAdd(Opts,'GitHub Enterprise Server');
   If AskSelect('What account do you want to log into?',Opts)=0 Then Host:='github.com'
   Else Host:=AskLine('GHE hostname:','');
  End
  Else If OptHas('with-token')Then Host:='github.com'
  Else Die('--hostname required when not running interactively');
 End;
 ApiHost:=Host;
 Web:=OptHas('web');
 If OptHas('with-token')Then Begin
  Tok:=TrimStr(FirstLine(ReadStdin));
  If Tok='' Then Die('no token found on standard input');
 End
 Else Begin
  If(not Web)and InteractiveOk Then Begin
   SClear(Opts);SAdd(Opts,'Login with a web browser');SAdd(Opts,'Paste an authentication token');
   Web:=AskSelect('How would you like to authenticate GitHub CLI?',Opts)=0;
  End
  Else If not InteractiveOk Then Web:=True;
  If Proto='' Then Begin
   If InteractiveOk Then Begin
    SClear(Opts);SAdd(Opts,'HTTPS');SAdd(Opts,'SSH');
    If AskSelect('What is your preferred protocol for Git operations on this host?',Opts)=0 Then
      Proto:='https' Else Proto:='ssh';
   End
   Else Proto:='https';
  End;
  If Web Then Begin
   Sc:='repo,read:org,gist';
   OptList('scopes',Sl);
   For I:=0 to Sl.N-1 do If Pos(Sl.A[I],Sc)=0 Then Sc:=Sc+','+Sl.A[I];
   WebForm(R,Host,'/login/device/code','client_id='+ClientId+'&scope='+UrlEnc(Sc,False));
   J:=JParse(R.RespBody);
   If(R.Status<>200)or(J<0)Then Die('failed to authenticate via web browser: '+ErrText(R));
   Dev:=JS(J,'device_code');UCode:=JS(J,'user_code');Uri:=JS(J,'verification_uri');
   Interval:=JI(J,'interval');If Interval<=0 Then Interval:=5;
   WriteLn(StdErr,'! First copy your one-time code: ',UCode);
   If InteractiveOk Then Begin
    Write(StdErr,'Press Enter to open ',GitHostName(Host),' in your browser... ');
    ReadLine_;
    OpenBrowser(Uri);
   End
   Else WriteLn(StdErr,'Open this URL to continue in your web browser: ',Uri);
   Tok:='';
   For I:=1 to 200 do Begin
    SleepSec(Interval);
    WebForm(R,Host,'/login/oauth/access_token','client_id='+ClientId+'&device_code='+Dev+
      '&grant_type=urn:ietf:params:oauth:grant-type:device_code');
    J:=JParse(R.RespBody);
    If J<0 Then Continue;
    If JS(J,'access_token')<>'' Then Begin Tok:=JS(J,'access_token');Break;End;
    Sc:=JS(J,'error');
    If Sc='slow_down' Then Inc(Interval,5)
    Else If Sc<>'authorization_pending' Then Die('authentication failed: '+JS(J,'error_description'));
   End;
   If Tok='' Then Die('authentication timed out');
  End
  Else Begin
   WriteLn(StdErr,'Tip: you can generate a Personal Access Token here https://',GitHostName(Host),
     '/settings/tokens');
   WriteLn(StdErr,'The minimum required scopes are ''repo'', ''read:org''.');
   Tok:=ReadSecret('? Paste your authentication token: ');
  End;
 End;
 User:=CheckToken(Host,Tok,Scopes,Valid);
 If not Valid Then Die('error validating token: HTTP 401: Bad credentials');
 If(Scopes<>'')Then Begin
  If not HasScope(Scopes,'repo')Then Die('error validating token: missing required scope ''repo''');
  If not(HasScope(Scopes,'read:org')or HasScope(Scopes,'admin:org'))Then
    Die('error validating token: missing required scope ''read:org''');
 End;
 If Proto='' Then Proto:='https';
 StoreLogin(Host,User,Tok,Proto);
 WriteLn(StdErr,'- gh config set -h ',GitHostName(Host),' git_protocol ',Proto);
 WriteLn(StdErr,#226#156#147' Configured git protocol');
 WriteLn(StdErr,#226#156#147' Logged in as ',User);
End;

Procedure ListHosts(Var Hosts:TSList);
Var
 Src:AnsiString;
 H:AnsiString;
Begin
 YSub(HostsY,'',Hosts);
 H:=GetEnv('GH_HOST');
 If(H<>'')and(SIndex(Hosts,H)<0)and(TokenEnvName(H,Src)<>'')Then SAdd(Hosts,H);
 If(SIndex(Hosts,'github.com')<0)and(TokenEnvName('github.com',Src)<>'')Then SAdd(Hosts,'github.com');
End;

Procedure CmdAuthStatus;
Var
 Hosts:TSList;
 I:LongInt;
 H,Tok,Src,User,Scopes:AnsiString;
 Valid,Any_,Failed:Boolean;
Begin
 CmdBegin('auth status','');
 Opt('active','a','','Display the active account only@@Affiche seulement le compte actif');
 Opt('hostname','h','string','Check only a specific hostname''s auth status@@V'+#130+'rifie seulement l''h'+#147+'te indiqu'+#130+'');
 Opt('show-token','t','','Display the auth token@@Affiche le jeton d''authentification');
 CmdLong('Verifies and displays information about your authentication state.@@V'+#130+'rifie et affiche l'''+#130+'tat de votre authentification.');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 ListHosts(Hosts);
 If OptHas('hostname')Then Begin
  If SIndex(Hosts,OptGet('hostname'))<0 Then Begin
   WriteLn(StdErr,'You are not logged into any accounts on ',OptGet('hostname'));
   Halt(1);
  End;
  SClear(Hosts);SAdd(Hosts,OptGet('hostname'));
 End;
 If Hosts.N=0 Then Begin
  WriteLn(StdErr,'You are not logged into any GitHub hosts. To log in, run: gh auth login');
  Halt(1);
 End;
 Failed:=False;
 For I:=0 to Hosts.N-1 do Begin
  H:=Hosts.A[I];
  Tok:=HostToken(H,Src);
  WriteLn(GitHostName(H));
  User:=CheckToken(H,Tok,Scopes,Valid);
  If Valid Then Begin
   WriteLn('  '#226#156#147' Logged in to ',GitHostName(H),' account ',User,' (',BaseName(Src),')');
   WriteLn('  - Active account: true');
   WriteLn('  - Git operations protocol: ',CfgGet('git_protocol',H));
   If OptHas('show-token')Then WriteLn('  - Token: ',Tok) Else WriteLn('  - Token: ',MaskTok(Tok));
   If Scopes<>'' Then Begin
    Scopes:=ReplaceAll(Scopes,' ','');
    WriteLn('  - Token scopes: ''',ReplaceAll(Scopes,',',''', '''),'''');
   End
   Else If Pos('github_pat_',Tok)=1 Then WriteLn('  - Token scopes: none');
  End
  Else Begin
   Failed:=True;
   WriteLn('  X Failed to log in to ',GitHostName(H),' account ',YGet(HostsY,H+'|user'),' (',BaseName(Src),')');
   WriteLn('  - Active account: true');
   WriteLn('  - The token in ',BaseName(Src),' is invalid.');
   WriteLn('  - To re-authenticate, run: gh auth login -h ',GitHostName(H));
   WriteLn('  - To forget about this account, run: gh auth logout -h ',GitHostName(H));
  End;
 End;
 If Failed Then Halt(1);
End;

Procedure CmdAuthLogout;
Var
 Host,User:AnsiString;
 Hosts,Users:TSList;
 Cur:AnsiString;
Begin
 CmdBegin('auth logout','');
 Opt('hostname','h','string','The hostname of the GitHub instance to log out of@@L''h'+#147+'te de l''instance GitHub dont fermer la session');
 Opt('user','u','string','The account to log out of@@Le compte dont fermer la session');
 CmdLong('Remove authentication for a GitHub account.@@Supprime l''authentification d''un compte GitHub.');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 ListHosts(Hosts);
 Host:=OptGet('hostname');
 If Host='' Then Begin
  If Hosts.N=0 Then Begin
   WriteLn(StdErr,'You are not logged into any GitHub hosts. To log in, run: gh auth login');
   Halt(1);
  End;
  Host:=Hosts.A[0];
 End;
 If(SIndex(Hosts,Host)<0)Then Begin
  WriteLn(StdErr,'You are not logged into any accounts on ',Host);
  Halt(1);
 End;
 Cur:=YGet(HostsY,Host+'|user');
 User:=OptGet('user');
 If User='' Then User:=Cur;
 YSub(HostsY,Host+'|users|',Users);
 If(User<>'')and(SIndex(Users,User)>=0)Then YDel(HostsY,Host+'|users|'+User);
 YSub(HostsY,Host+'|users|',Users);
 If(User=Cur)or(Users.N=0)Then Begin
  If Users.N>0 Then Begin
   YSet(HostsY,Host+'|user',Users.A[0]);
   YSet(HostsY,Host+'|oauth_token',YGet(HostsY,Host+'|users|'+Users.A[0]+'|oauth_token'));
  End
  Else YDel(HostsY,Host);
 End;
 SaveHosts;
 WriteLn(StdErr,#226#156#147' Logged out of ',GitHostName(Host),' account ',User);
End;

Procedure CmdAuthToken;
Var
 Host,Tok,Src,U:AnsiString;
Begin
 CmdBegin('auth token','');
 Opt('hostname','h','string','The hostname of the GitHub instance authenticated with@@L''h'+#147+'te de l''instance GitHub');
 Opt('secure-storage','','','Search only secure credential store for authentication token@@Cherche seulement dans le trousseau s'+#130+'curis'+#130+'');
 Opt('user','u','string','The account to output the token for@@Le compte dont afficher le jeton');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 Host:=OptGet('hostname');
 If Host='' Then Host:=DefaultHost;
 U:=OptGet('user');
 If U<>'' Then Tok:=YGet(HostsY,Host+'|users|'+U+'|oauth_token') Else Tok:=HostToken(Host,Src);
 If Tok='' Then Die('no oauth token found for '+Host);
 WriteLn(Tok);
End;

Procedure CmdAuthSwitch;
Var
 Host,User:AnsiString;
 Users,Hosts:TSList;
 I:LongInt;
Begin
 CmdBegin('auth switch','');
 Opt('hostname','h','string','The hostname of the GitHub instance to switch account for@@L''h'+#147+'te de l''instance GitHub');
 Opt('user','u','string','The account to switch to@@Le compte vers lequel basculer');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 ListHosts(Hosts);
 Host:=OptGet('hostname');
 If Host='' Then Begin
  If Hosts.N=0 Then Die('not logged in to any hosts');
  Host:=Hosts.A[0];
 End;
 YSub(HostsY,Host+'|users|',Users);
 If Users.N<2 Then Die('the host '+Host+' only has one account');
 User:=OptGet('user');
 If User='' Then Begin
  For I:=0 to Users.N-1 do If Users.A[I]<>YGet(HostsY,Host+'|user')Then Begin User:=Users.A[I];Break;End;
 End;
 If SIndex(Users,User)<0 Then Die('no account '+User+' found on '+Host);
 YSet(HostsY,Host+'|user',User);
 YSet(HostsY,Host+'|oauth_token',YGet(HostsY,Host+'|users|'+User+'|oauth_token'));
 SaveHosts;
 WriteLn(StdErr,#226#156#147' Switched active account for ',GitHostName(Host),' to ',User);
End;

Procedure CmdAuthRefresh;
Var
 Host,Sc,Tok,User,Scopes,Dev,UCode,Uri:AnsiString;
 R:THttpReq;
 J,Interval,I:LongInt;
 Sl:TSList;
 Valid:Boolean;
Begin
 CmdBegin('auth refresh','');
 Opt('clipboard','c','','Copy one-time OAuth device code to clipboard@@Copie le code '+#133+' usage unique dans le presse-papiers');
 Opt('hostname','h','string','The GitHub host to use for authentication@@L''h'+#147+'te GitHub utilis'+#130+' pour l''authentification');
 Opt('insecure-storage','','','Save credentials in plain text instead of credential store@@Enregistre les identifiants en clair');
 Opt('remove-scopes','r','*strings','Authentication scopes to remove from gh''s OAuth token@@Port'+#130+'es '+#133+' retirer du jeton');
 Opt('reset-scopes','','','Reset authentication scopes to the default minimum set of scopes@@R'+#130+'tablit les port'+#130+'es minimales par d'+#130+'faut');
 Opt('scopes','s','*strings','Additional authentication scopes for gh to have@@Port'+#130+'es suppl'+#130+'mentaires pour gh');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 Host:=OptGet('hostname');
 If Host='' Then Host:=DefaultHost;
 ApiHost:=Host;
 If YGet(HostsY,Host+'|oauth_token')='' Then Begin
  WriteLn(StdErr,'You are not logged into any GitHub hosts. To log in, run: gh auth login');
  Halt(1);
 End;
 Tok:=TokenOf(Host);
 CheckToken(Host,Tok,Scopes,Valid);
 Sc:='repo,read:org,gist';
 If not OptHas('reset-scopes')Then Begin
  Scopes:=ReplaceAll(Scopes,' ','');
  If Scopes<>'' Then Sc:=Scopes+','+Sc;
 End;
 OptList('scopes',Sl);
 For I:=0 to Sl.N-1 do Sc:=Sc+','+Sl.A[I];
 WebForm(R,Host,'/login/device/code','client_id='+ClientId+'&scope='+UrlEnc(Sc,False));
 J:=JParse(R.RespBody);
 If(R.Status<>200)or(J<0)Then Die('failed to authenticate via web browser: '+ErrText(R));
 Dev:=JS(J,'device_code');UCode:=JS(J,'user_code');Uri:=JS(J,'verification_uri');
 Interval:=JI(J,'interval');If Interval<=0 Then Interval:=5;
 WriteLn(StdErr,'! First copy your one-time code: ',UCode);
 If InteractiveOk Then Begin
  Write(StdErr,'Press Enter to open ',GitHostName(Host),' in your browser... ');
  ReadLine_;OpenBrowser(Uri);
 End
 Else WriteLn(StdErr,'Open this URL to continue in your web browser: ',Uri);
 Tok:='';
 For I:=1 to 200 do Begin
  SleepSec(Interval);
  WebForm(R,Host,'/login/oauth/access_token','client_id='+ClientId+'&device_code='+Dev+
    '&grant_type=urn:ietf:params:oauth:grant-type:device_code');
  J:=JParse(R.RespBody);
  If J<0 Then Continue;
  If JS(J,'access_token')<>'' Then Begin Tok:=JS(J,'access_token');Break;End;
  If JS(J,'error')='slow_down' Then Inc(Interval,5)
  Else If JS(J,'error')<>'authorization_pending' Then Die('authentication failed: '+JS(J,'error_description'));
 End;
 If Tok='' Then Die('authentication timed out');
 User:=CheckToken(Host,Tok,Scopes,Valid);
 StoreLogin(Host,User,Tok,'');
 WriteLn(StdErr,#226#156#147' Authentication complete.');
End;

{ gh auth git-credential get|store|erase }
Procedure CmdAuthGitCred;
Var
 Op,Ln,Host,Proto,Tok,Src,User:AnsiString;
 P:LongInt;
Begin
 Op:=ParamStr(ArgStart);
 If Op<>'get' Then Halt(0);
 Host:='';
 While not Eof(Input)do Begin
  ReadLn(Ln);
  Ln:=ReplaceAll(Ln,#13,'');
  If Ln='' Then Break;
  P:=Pos('=',Ln);
  If P>0 Then Begin
   If Copy(Ln,1,P-1)='host' Then Host:=Copy(Ln,P+1,Length(Ln));
   If Copy(Ln,1,P-1)='protocol' Then Proto:=Copy(Ln,P+1,Length(Ln));
  End;
 End;
 If Host='' Then Halt(1);
 If Host='gist.github.com' Then Host:='github.com';
 Tok:=HostToken(Host,Src);
 If Tok='' Then Halt(1);
 User:=YGet(HostsY,Host+'|user');
 If User='' Then User:='x-access-token';
 WriteLn('protocol=https');
 WriteLn('host=',Host);
 WriteLn('username=',User);
 WriteLn('password=',Tok);
End;

Procedure CmdAuthSetupGit;
Var
 Hosts:TSList;
 I:LongInt;
 H,Helper:AnsiString;
Begin
 CmdBegin('auth setup-git','');
 Opt('force','f','','Force setup even if the host is not known@@Force la configuration m'+#136+'me si l''h'+#147+'te est inconnu');
 Opt('hostname','h','string','The hostname to configure git for@@L''h'+#147+'te pour lequel configurer git');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 ListHosts(Hosts);
 If OptHas('hostname')Then Begin
  If(SIndex(Hosts,OptGet('hostname'))<0)and not OptHas('force')Then
    Die('You are not logged into the GitHub host "'+OptGet('hostname')+'". Run gh auth login -h '+
      OptGet('hostname')+' to authenticate or provide `--force`');
  SClear(Hosts);SAdd(Hosts,OptGet('hostname'));
 End;
 If Hosts.N=0 Then Die('You are not logged into any GitHub hosts. Run gh auth login to authenticate.');
 Helper:='!'+Q(ParamStr(0))+' auth git-credential';
 For I:=0 to Hosts.N-1 do Begin
  H:=Hosts.A[I];
  RunShell('git config --global --replace-all credential.https://'+GitHostName(H)+'.helper ""');
  If RunShell('git config --global --add credential.https://'+GitHostName(H)+'.helper '+Q(Helper))<>0 Then
    Die('failed to configure git credential helper');
 End;
End;

{ ---------- config ---------- }

Procedure CmdConfigGet;
Var
 K,Host:AnsiString;
Begin
 CmdBegin('config get','<key>');
 Opt('host','h','string','Get per-host setting@@Lit le param'+#138+'tre d''un h'+#147+'te');
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 K:=Pos1(0);
 Host:=OptGet('host');
 If Host<>'' Then Begin
  If YHas(HostsY,Host+'|'+K)Then WriteLn(YGet(HostsY,Host+'|'+K)) Else Die('Could not find key '+K);
  Exit;
 End;
 If not CfgValid(K)Then Begin
  If YHas(CfgY,K)Then WriteLn(YGet(CfgY,K)) Else Begin WriteLn(StdErr,'Could not find key "',K,'"');Halt(1);End;
 End
 Else WriteLn(CfgGet(K,''));
End;

Procedure CmdConfigSet;
Var
 K,V,Host:AnsiString;
Begin
 CmdBegin('config set','<key> <value>');
 Opt('host','h','string','Set per-host setting@@D'+#130+'finit le param'+#138+'tre d''un h'+#147+'te');
 ParseArgs(ArgStart);
 NeedArgs(2,2);
 K:=Pos1(0);V:=Pos1(1);
 If K='git_protocol' Then Begin
  If(V<>'https')and(V<>'ssh')Then Die('failed to set "git_protocol" to "'+V+'": valid values are https, ssh');
 End
 Else If(K='prompt')or(K='color_labels')or(K='accessible_colors')or(K='accessible_prompter')or
   (K='spinner')or(K='telemetry')Then Begin
  If(V<>'enabled')and(V<>'disabled')Then
    Die('failed to set "'+K+'" to "'+V+'": valid values are enabled, disabled');
 End
 Else If not CfgValid(K)Then WriteLn(StdErr,'! warning: ''',K,''' is not a known configuration key');
 Host:=OptGet('host');
 If Host<>'' Then Begin YSet(HostsY,Host+'|'+K,V);SaveHosts;End
 Else Begin YSet(CfgY,K,V);SaveConfig;End;
End;

Procedure CmdConfigList;
Var
 I:LongInt;
 Host:AnsiString;
Begin
 CmdBegin('config list','');
 Opt('host','h','string','Get per-host configuration@@Lit la configuration d''un h'+#147+'te');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 Host:=OptGet('host');
 For I:=0 to NCfg-1 do WriteLn(CfgNames[I],'=',CfgGet(CfgNames[I],Host));
End;

Procedure CmdConfigClear;
Begin
 CmdBegin('config clear-cache','');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 WriteLn(StdErr,#226#156#147' Cleared the cache');
End;

{ ---------- alias ---------- }

Function IsBuiltinCmd(Const Nm:AnsiString):Boolean;
Var
 I:LongInt;
Begin
 IsBuiltinCmd:=False;
 For I:=0 to NDesc-1 do If Descs[I].P=Nm Then IsBuiltinCmd:=True;
End;

{ premier mot / deux premiers mots d'une expansion d'alias }
Function Trim1(Const S:AnsiString):AnsiString;
Var
 L:TSList;
Begin
 SplitStr(TrimStr(S),' ',L);
 Trim1:=L.A[0];
End;

Function Trim2(Const S:AnsiString):AnsiString;
Var
 L:TSList;
Begin
 SplitStr(TrimStr(S),' ',L);
 If L.N>=2 Then Trim2:=L.A[0]+' '+L.A[1] Else Trim2:=L.A[0];
End;

Procedure CmdAliasSet;
Var
 Nm,Ex:AnsiString;
Begin
 CmdBegin('alias set','<alias> <expansion>');
 Opt('clobber','','','Overwrite existing aliases of the same name@@Remplace un alias existant de m'+#136+'me nom');
 Opt('shell','s','','Declare an alias to be passed through a shell interpreter@@D'+#130+'clare un alias ex'+#130+'cut'+#130+' par un interpr'+#130+'teur shell');
 CmdLong('Define a word that will expand to a full gh command when invoked.@@D'+#130+'finit un mot qui se d'+#130+'veloppe en une commande gh compl'+#138+'te.');
 CmdExample('$ gh alias set pv ''pr view''');
 CmdExample('$ gh alias set bugs ''issue list --label=bug''');
 CmdExample('$ gh alias set --shell igrep ''gh issue list --label="$1" | grep "$2"''');
 ParseArgs(ArgStart);
 NeedArgs(2,2);
 Nm:=Pos1(0);Ex:=Pos1(1);
 If Ex='-' Then Ex:=TrimStr(ReadStdin);
 If OptHas('shell')and(Ex[1]<>'!')Then Ex:='!'+Ex;
 If(IsBuiltinCmd(Nm))Then Die('could not create alias: "'+Nm+'" is already a gh command');
 If YHas(CfgY,'aliases|'+Nm)and not OptHas('clobber')Then
   Die('could not create alias: "'+Nm+'" is already an alias for "'+YGet(CfgY,'aliases|'+Nm)+'"'#10'use `--clobber` to overwrite');
 If(Ex<>'')and(Ex[1]<>'!')and not IsBuiltinCmd(Trim1(Ex))and not IsBuiltinCmd(Trim2(Ex))Then
   Die('could not create alias: '+Ex+' does not correspond to a gh command');
 WriteLn(StdErr,'- Adding alias for ',Nm,': ',Ex);
 YSet(CfgY,'aliases|'+Nm,Ex);
 SaveConfig;
 WriteLn(StdErr,#226#156#147' Added alias.');
End;

Procedure CmdAliasList;
Var
 N:TSList;
 I:LongInt;
Begin
 CmdBegin('alias list','');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 YSub(CfgY,'aliases|',N);
 If N.N=0 Then Begin
  WriteLn(StdErr,'no aliases configured');
  Halt(1);
 End;
 SSort(N);
 TblBegin('');
 For I:=0 to N.N-1 do TblRow(N.A[I]+':'+#9+YGet(CfgY,'aliases|'+N.A[I]));
 TblPrint;
End;

Procedure CmdAliasDelete;
Var
 I:LongInt;
 N:TSList;
 Ex:AnsiString;
Begin
 CmdBegin('alias delete','{<alias> | --all}');
 Opt('all','','','Delete all aliases@@Supprime tous les alias');
 ParseArgs(ArgStart);
 If OptHas('all')Then Begin
  YSub(CfgY,'aliases|',N);
  For I:=0 to N.N-1 do YDel(CfgY,'aliases|'+N.A[I]);
  YDel(CfgY,'aliases');
  SaveConfig;
  WriteLn(StdErr,#226#156#147' Deleted ',N.N,' aliases');
  Exit;
 End;
 NeedArgs(1,-1);
 For I:=0 to PosArgs.N-1 do Begin
  If not YHas(CfgY,'aliases|'+PosArgs.A[I])Then Die('no such alias '+PosArgs.A[I]);
  Ex:=YGet(CfgY,'aliases|'+PosArgs.A[I]);
  YDel(CfgY,'aliases|'+PosArgs.A[I]);
  WriteLn(StdErr,#226#156#147' Deleted alias ',PosArgs.A[I],'; was ',Ex);
 End;
 SaveConfig;
End;

Procedure CmdAliasImports;
Var
 F,Txt:AnsiString;
 Y:TYaml;
 I,Cnt:LongInt;
 Nm:AnsiString;
Begin
 CmdBegin('alias imports','[<filename> | -]');
 Opt('clobber','','','Overwrite existing aliases of the same name@@Remplace un alias existant de m'+#136+'me nom');
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 F:=Pos1(0);
 If F='-' Then Begin
  Txt:=ReadStdin;
  F:=TmpFile('.yml');WriteAll(F,Txt);
 End;
 If not FileExists_(F)Then Die('open '+F+': no such file or directory');
 YamlLoad(F,Y);
 Cnt:=0;
 For I:=0 to Y.K.N-1 do Begin
  Nm:=Y.K.A[I];
  If IsBuiltinCmd(Nm)Then Begin WriteLn(StdErr,'X Could not import alias ',Nm,': already a gh command');Continue;End;
  If YHas(CfgY,'aliases|'+Nm)and not OptHas('clobber')Then Begin
   WriteLn(StdErr,'X Could not import alias ',Nm,': already taken');Continue;
  End;
  YSet(CfgY,'aliases|'+Nm,Y.V.A[I]);
  WriteLn(StdErr,#226#156#147' Added alias ',Nm);
  Inc(Cnt);
 End;
 SaveConfig;
End;
{ ------------------------------------------------------------------ }
{ gh api, browse, status, version, completion                         }
{ ------------------------------------------------------------------ }

Var
 PutSegs:TSList;
 PutVal:LongInt;

{ descend dans l'objet JSON selon les segments a[b][] }
Procedure PutRec(Cur,I:LongInt);
Var
 Seg:AnsiString;
 Child,Cont:LongInt;
 Last:Boolean;
Begin
 Seg:=PutSegs.A[I];
 Last:=I=PutSegs.N-1;
 If JP[Cur].Kind=JK_ARR Then Begin
  If Last Then ArrAdd(Cur,PutVal)
  Else Begin
   Cont:=MkObj;
   ArrAdd(Cur,Cont);
   PutRec(JP[Cur].Last,I);
  End;
  Exit;
 End;
 If Last Then Begin ObjSet(Cur,Seg,PutVal);Exit;End;
 Child:=JGet(Cur,Seg);
 If(Child<0)or not(JP[Child].Kind in[JK_ARR,JK_OBJ])Then Begin
  If PutSegs.A[I+1]='' Then Cont:=MkArr Else Cont:=MkObj;
  ObjSet(Cur,Seg,Cont);
  Child:=JGet(Cur,Seg);
 End;
 PutRec(Child,I+1);
End;

Procedure PutNested(Obj:LongInt;Const Key:AnsiString;V:LongInt);
Var
 B,I:LongInt;
 Rest:AnsiString;
Begin
 B:=Pos('[',Key);
 SClear(PutSegs);
 If B=0 Then SAdd(PutSegs,Key)
 Else Begin
  SAdd(PutSegs,Copy(Key,1,B-1));
  Rest:=Copy(Key,B,Length(Key));
  While(Rest<>'')and(Rest[1]='[')do Begin
   I:=Pos(']',Rest);
   If I=0 Then Break;
   SAdd(PutSegs,Copy(Rest,2,I-2));
   Rest:=Copy(Rest,I+1,Length(Rest));
  End;
 End;
 PutVal:=V;
 PutRec(Obj,0);
End;

{ remplace {owner}, {repo} et {branch} }
Function ExpandPlaceholders(Const S:AnsiString):AnsiString;
Var
 R:AnsiString;
Begin
 R:=S;
 If(Pos('{owner}',R)>0)or(Pos('{repo}',R)>0)or(Pos('{branch}',R)>0)Then Begin
  ResolveRepo(False);
  If Pos('{owner}',R)>0 Then Begin
   If RepoOwner='' Then Die('unable to determine the current repository for {owner}');
   R:=ReplaceAll(R,'{owner}',RepoOwner);
  End;
  If Pos('{repo}',R)>0 Then Begin
   If RepoName='' Then Die('unable to determine the current repository for {repo}');
   R:=ReplaceAll(R,'{repo}',RepoName);
  End;
  If Pos('{branch}',R)>0 Then R:=ReplaceAll(R,'{branch}',CurrentBranch);
 End;
 ExpandPlaceholders:=R;
End;

{ valeur typee d'un champ -F }
Function TypedValue(Const V:AnsiString):LongInt;
Var
 S:AnsiString;
 N:Int64;
 Code:LongInt;
Begin
 If(V<>'')and(V[1]='@')Then Begin
  If V='@-' Then S:=ReadStdin
  Else If not ReadAll(Copy(V,2,Length(V)),S)Then Die('open '+Copy(V,2,Length(V))+': no such file or directory');
  TypedValue:=MkStr(S);Exit;
 End;
 If V='true' Then Begin TypedValue:=MkBool(True);Exit;End;
 If V='false' Then Begin TypedValue:=MkBool(False);Exit;End;
 If V='null' Then Begin TypedValue:=MkNull;Exit;End;
 Val(V,N,Code);
 If(Code=0)and(V<>'')Then Begin TypedValue:=MkNum(N);Exit;End;
 TypedValue:=MkStr(ExpandPlaceholders(V));
End;

Function TrimJsonStr(N:LongInt):AnsiString;
Begin
 If JP[N].Kind=JK_NULL Then TrimJsonStr:='' Else TrimJsonStr:=ToStr(N);
End;

Function QueryOf(Obj:LongInt):AnsiString;
Var
 C,D:LongInt;
 L:TSList;
Begin
 SClear(L);
 C:=JP[Obj].First;
 While C>=0 do Begin
  If JP[C].Kind=JK_ARR Then Begin
   D:=JP[C].First;
   While D>=0 do Begin SAdd(L,UrlEnc(JP[C].Key,False)+'[]='+UrlEnc(TrimJsonStr(D),False));D:=JP[D].Next;End;
  End
  Else SAdd(L,UrlEnc(JP[C].Key,False)+'='+UrlEnc(TrimJsonStr(C),False));
  C:=JP[C].Next;
 End;
 QueryOf:=JoinList(L,'&');
End;

{ affiche un corps de reponse }
Procedure ApiPrintBody(Const Body:AnsiString;Const Pretty:Boolean);
Var
 N:LongInt;
Begin
 If JqExpr<>'' Then Begin
  If not JqExec(JqExpr,Body,OutTTY)Then Halt(1);
  Exit;
 End;
 If TmplText<>'' Then Begin
  If not TmplExec(TmplText,Body)Then Halt(1);
  Exit;
 End;
 If OutTTY and(Body<>'')and(Body[1]in['{','['])Then Begin
  N:=JParse(Body);
  If N>=0 Then Begin JPrint(N);Exit;End;
 End;
 If(Body<>'')and(Body[Length(Body)]<>#10)Then WriteLn(Body) Else Write(Body);
End;

{ cherche un objet pageInfo avec hasNextPage }
Function FindPageInfo(N:LongInt):LongInt;
Var
 C,R:LongInt;
Begin
 FindPageInfo:=-1;
 If N<0 Then Exit;
 If JP[N].Kind=JK_OBJ Then Begin
  If(JP[N].Key='pageInfo')Then Begin FindPageInfo:=N;Exit;End;
  C:=JP[N].First;
  While C>=0 do Begin
   R:=FindPageInfo(C);
   If R>=0 Then Begin FindPageInfo:=R;Exit;End;
   C:=JP[C].Next;
  End;
 End
 Else If JP[N].Kind=JK_ARR Then Begin
  C:=JP[N].First;
  While C>=0 do Begin
   R:=FindPageInfo(C);
   If R>=0 Then Begin FindPageInfo:=R;Exit;End;
   C:=JP[C].Next;
  End;
 End;
End;

Procedure CmdApi;
Var
 Ep,Method,Url,Body,Q_,Err,Kv,Key,Val_,Host:AnsiString;
 Raw,Typed,Hdrs,Pages:TSList;
 Fields,Vars:LongInt;
 I,P,J,Pg:LongInt;
 R:THttpReq;
 Graph,HasFields,Paginate,Slurp,More:Boolean;
 Cursor,Msg:AnsiString;
 PI_:LongInt;
 InputF,InputBody:AnsiString;
Begin
 CmdBegin('api','<endpoint>');
 Opt('cache','','duration','Cache the response, e.g. "3600s", "60m", "1h"@@Met la r'+#130+'ponse en cache, ex. : "3600s", "60m", "1h"');
 Opt('field','F','*key=value','Add a typed parameter in key=value format (use "@<path>" to read from a file)@@Ajoute un param'+#138+'tre typ'+#130+' au format cl'+#130+'=valeur ("@<chemin>" lit un fichier)');
 Opt('header','H','*key:value','Add a HTTP request header in key:value format@@Ajoute un en-t'+#136+'te HTTP au format cl'+#130+':valeur');
 Opt('hostname','','string','The GitHub hostname for the request (default "github.com")@@L''h'+#147+'te GitHub de la requ'+#136+'te (d'+#130+'faut "github.com")');
 Opt('include','i','','Include HTTP response status line and headers in the output@@Inclut la ligne d'''+#130+'tat et les en-t'+#136+'tes HTTP dans la sortie');
 Opt('input','','file','The file to use as body for the HTTP request (use "-" to read from standard input)@@Le fichier utilis'+#130+' comme corps de la requ'+#136+'te ("-" lit l''entr'+#130+'e standard)');
 Opt('jq','q','string','Query to select values from the response using jq syntax@@Expression jq pour s'+#130+'lectionner des valeurs dans la r'+#130+'ponse');
 Opt('method','X','string','The HTTP method for the request (default "GET")@@La m'+#130+'thode HTTP de la requ'+#136+'te (d'+#130+'faut "GET")');
 Opt('paginate','','','Make additional HTTP requests to fetch all pages of results@@Effectue des requ'+#136+'tes suppl'+#130+'mentaires pour r'+#130+'cup'+#130+'rer toutes les pages');
 Opt('preview','p','*names','GitHub API preview names to request (without the "-preview" suffix)@@Noms des aper'+#135+'us de l''API '+#133+' demander');
 Opt('raw-field','f','*key=value','Add a string parameter in key=value format@@Ajoute un param'+#138+'tre texte au format cl'+#130+'=valeur');
 Opt('silent','','','Do not print the response body@@N''affiche pas le corps de la r'+#130+'ponse');
 Opt('slurp','','','Use with "--paginate" to return an array of all pages of either JSON arrays or objects@@Avec "--paginate", renvoie un tableau de toutes les pages');
 Opt('template','t','string','Format JSON output using a Go template; see "gh help formatting"@@Formate la sortie JSON avec un mod'+#138+'le Go');
 Opt('verbose','','','Include full HTTP request and response in the output@@Inclut la requ'+#136+'te et la r'+#130+'ponse HTTP compl'+#138+'tes');
 CmdLong('Makes an authenticated HTTP request to the GitHub API and prints the response.@@Effectue une requ'+#136+'te HTTP authentifi'+#130+'e vers l''API GitHub et affiche la r'+#130+'ponse.');
 CmdExample('# list releases in the current repository');
 CmdExample('$ gh api repos/{owner}/{repo}/releases');
 CmdExample('# create a comment on an issue');
 CmdExample('$ gh api repos/{owner}/{repo}/issues/123/comments -f body=''Hi from CLI''');
 CmdExample('# get the stargazer count with jq');
 CmdExample('$ gh api repos/cli/cli --jq ".stargazers_count"');
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 AllowAnon:=False;
 Ep:=ExpandPlaceholders(Pos1(0));
 Host:=OptGet('hostname');
 If Host='' Then Host:=DefaultHost;
 ApiHost:=Host;
 JqExpr:=OptGet('jq');TmplText:=OptGet('template');
 If(JqExpr<>'')and(TmplText<>'')Then Die2('cannot use `--jq` and `--template` at the same time',1);
 Graph:=(Ep='graphql');
 Fields:=MkObj;
 Vars:=MkObj;
 HasFields:=False;
 OptList('raw-field',Raw);OptList('field',Typed);
 For I:=0 to Raw.N+Typed.N-1 do Begin
  If I<Raw.N Then Kv:=Raw.A[I] Else Kv:=Typed.A[I-Raw.N];
  P:=Pos('=',Kv);
  If P=0 Then Die('field '+Kv+' requires a value separated by an ''='' sign');
  Key:=Copy(Kv,1,P-1);Val_:=Copy(Kv,P+1,Length(Kv));
  HasFields:=True;
  If I<Raw.N Then Begin
   If(Graph)and(Key<>'query')Then PutNested(Vars,Key,MkStr(Val_))
   Else If(Graph)Then PutNested(Fields,Key,MkStr(Val_))
   Else PutNested(Fields,Key,MkStr(Val_));
  End
  Else Begin
   If(Graph)and(Key<>'query')Then PutNested(Vars,Key,TypedValue(Val_))
   Else If Graph Then PutNested(Fields,Key,TypedValue(Val_))
   Else PutNested(Fields,Key,TypedValue(Val_));
  End;
 End;
 Method:=UpStr(OptGet('method'));
 If Method='' Then Begin
  If HasFields or OptHas('input')or Graph Then Method:='POST' Else Method:='GET';
 End;
 Paginate:=OptHas('paginate');Slurp:=OptHas('slurp');
 If Slurp and not Paginate Then Die2('`--paginate` required when passing `--slurp`',1);
 If Paginate and(Method<>'GET')and not Graph Then Die2('the `--paginate` option is not supported for non-GET requests',1);
 If Paginate and OptHas('input')Then Die2('the `--input` option is not supported with `--paginate`',1);
 If Graph Then Begin
  Url:=GraphqlUrlOf(Host);
  If JGet(Fields,'query')<0 Then Die2('GraphQL query is required: pass -f query=...',1);
 End
 Else Begin
  If StartsWith(Ep,'http://')or StartsWith(Ep,'https://')Then Url:=Ep
  Else Begin
   If Ep[1]<>'/' Then Ep:='/'+Ep;
   Url:=ApiBaseOf(Host)+Ep;
  End;
 End;
 Body:='';
 If OptHas('input')Then Begin
  InputF:=OptGet('input');
  If InputF='-' Then Body:=ReadStdin
  Else If not ReadAll(InputF,Body)Then Die('open '+InputF+': no such file or directory');
  If HasFields Then Url:=WithQuery(Url,QueryOf(Fields));
 End
 Else If HasFields and not Graph Then Begin
  If(Method='GET')or(Method='HEAD')Then Url:=WithQuery(Url,QueryOf(Fields))
  Else Body:=RawJson(Fields);
 End;
 OptList('header',Hdrs);
 Err:='';
 SClear(Pages);
 Cursor:='';
 Pg:=0;
 Repeat
  Inc(Pg);
  If Graph Then Begin
   If Cursor<>'' Then PutNested(Vars,'endCursor',MkStr(Cursor));
   Msg:='{"query":'+JQ(JS(Fields,'query'));
   If JP[Vars].Cnt>0 Then Msg:=Msg+',"variables":'+RawJson(Vars);
   Body:=Msg+'}';
  End;
  ReqInit(R,Method,Url,TokenOf(Host));
  If Body<>'' Then Begin
   R.BodyStr:=Body;
   R.Headers:='Content-Type: application/json'#13#10;
  End;
  For I:=0 to Hdrs.N-1 do Begin
   P:=Pos(':',Hdrs.A[I]);
   If P=0 Then Die('header '+Hdrs.A[I]+' requires a value separated by a colon');
   R.Headers:=R.Headers+TrimStr(Copy(Hdrs.A[I],1,P-1))+': '+TrimStr(Copy(Hdrs.A[I],P+1,Length(Hdrs.A[I])))+#13#10;
  End;
  If OptHas('preview')Then Begin
   OptList('preview',Raw);
   For I:=0 to Raw.N-1 do R.Headers:=R.Headers+'Accept: application/vnd.github.'+Raw.A[I]+'-preview+json'#13#10;
  End;
  If OptHas('verbose')Then Begin
   WriteLn(StdErr,'* Request to ',Url);
   WriteLn(StdErr,'> ',Method,' ',Url);
  End;
  If TokenOf(Host)='' Then Begin RequireAuth;End;
  HttpDo(R);
  If R.Err<>'' Then Die(R.Err);
  If OptHas('verbose')Then WriteLn(StdErr,'< HTTP ',R.Status);
  If OptHas('include')Then Begin
   Write(R.RespHeaders);
   If(R.RespHeaders<>'')and(R.RespHeaders[Length(R.RespHeaders)]<>#10)Then WriteLn;
   WriteLn;
  End;
  More:=False;
  If(R.Status<200)or(R.Status>=300)Then Begin
   If not OptHas('silent')and(TrimStr(R.RespBody)<>'')Then ApiPrintBody(R.RespBody,False);
   J:=JParse(R.RespBody);
   Msg:=JS(J,'message');
   If(Msg='')and Graph Then Msg:=JS(J,'errors');
   If Msg='' Then Msg:=ReasonOf(R.Status);
   WriteLn(StdErr,'gh: ',Msg,' (HTTP ',R.Status,')');
   If R.Status=401 Then WriteLn(StdErr,'Try authenticating with:  gh auth login');
   Halt(1);
  End;
  If Graph Then Begin
   J:=JParse(R.RespBody);
   If(J>=0)and(JGet(J,'errors')>=0)Then Begin
    If not OptHas('silent')Then ApiPrintBody(R.RespBody,False);
    WriteLn(StdErr,'gh: ',JS(JP[JGet(J,'errors')].First,'message'));
    Halt(1);
   End;
   If Paginate and(J>=0)Then Begin
    PI_:=FindPageInfo(J);
    If(PI_>=0)and JB(PI_,'hasNextPage')Then Begin Cursor:=JS(PI_,'endCursor');More:=True;End;
   End;
  End
  Else If Paginate Then Begin
   Url:=LinkNext(R.RespHeaders);
   More:=Url<>'';
  End;
  If Slurp Then SAdd(Pages,TrimStr(R.RespBody))
  Else If not OptHas('silent')Then ApiPrintBody(R.RespBody,False);
 Until not More;
 If Slurp Then Begin
  Msg:='['+JoinList(Pages,',')+']';
  If not OptHas('silent')Then ApiPrintBody(Msg,False);
 End;
End;

Function IsHex_(Const S:AnsiString):Boolean;
Var
 I:LongInt;
Begin
 IsHex_:=S<>'';
 For I:=1 to Length(S)do If not(S[I]in['0'..'9','a'..'f','A'..'F'])Then IsHex_:=False;
End;

{ ---------- browse ---------- }

Procedure CmdBrowse;
Var
 Url,Arg,Br,Path:AnsiString;
 N,P:LongInt;
Begin
 CmdBegin('browse','[<number> | <path> | <commit-sha>]');
 Opt('branch','b','string','Select another branch by passing in the branch name@@S'+#130+'lectionne une autre branche');
 Opt('commit','c','','Open the last commit@@Ouvre le dernier commit');
 Opt('no-browser','n','','Print destination URL instead of opening the browser@@Affiche l''URL de destination au lieu d''ouvrir le navigateur');
 Opt('projects','p','','Open repository projects@@Ouvre les projets du d'+#130+'p'+#147+'t');
 OptRepo;
 Opt('releases','r','','Open repository releases@@Ouvre les versions du d'+#130+'p'+#147+'t');
 Opt('settings','s','','Open repository settings@@Ouvre les param'+#138+'tres du d'+#130+'p'+#147+'t');
 Opt('wiki','w','','Open repository wiki@@Ouvre le wiki du d'+#130+'p'+#147+'t');
 CmdLong('Transition from the terminal to the web browser to view and interact with:@@Passe du terminal au navigateur pour consulter :'#10'- Issues'#10'- Pull requests'#10'- Repository content'#10'- Repository home page'#10'- Repository settings');
 CmdExample('$ gh browse');
 CmdExample('$ gh browse 217');
 CmdExample('$ gh browse --settings');
 CmdExample('$ gh browse main.go:312');
 ParseArgs(ArgStart);
 NeedArgs(0,1);
 NeedRepo;
 Url:=RepoWebUrl;
 Arg:=Pos1(0);
 Br:=OptGet('branch');
 If OptHas('projects')Then Url:=Url+'/projects'
 Else If OptHas('wiki')Then Url:=Url+'/wiki'
 Else If OptHas('settings')Then Url:=Url+'/settings'
 Else If OptHas('releases')Then Url:=Url+'/releases'
 Else If OptHas('commit')or((Arg<>'')and(Length(Arg)>=7)and(Length(Arg)<=40)and(ToInt(Arg,-1)<0)and
   (Pos('.',Arg)=0)and(Pos('/',Arg)=0)and(Pos(':',Arg)=0)and IsHex_(Arg))Then Begin
  If Arg='' Then Arg:=GitOut('rev-parse HEAD');
  Url:=Url+'/commit/'+Arg;
 End
 Else If Arg<>'' Then Begin
  N:=ToInt(Arg,-1);
  If(N<=0)and(Arg[1]='#')Then N:=ToInt(Copy(Arg,2,20),-1);
  If N>0 Then Url:=Url+'/issues/'+IStr(N)
  Else Begin
   Path:=Arg;
   P:=Pos(':',Path);
   If P>0 Then Begin
    Url:=Url+'/tree/'+IfThen_(Br<>'',Br,'HEAD')+'/'+UrlEnc(Copy(Path,1,P-1),True)+'#L'+Copy(Path,P+1,Length(Path));
   End
   Else Url:=Url+'/tree/'+IfThen_(Br<>'',Br,'HEAD')+'/'+UrlEnc(Path,True);
  End;
 End
 Else If Br<>'' Then Url:=Url+'/tree/'+Br;
 If OptHas('no-browser')Then WriteLn(Url)
 Else Begin
  OpenWeb(Url);
 End;
End;

{ ---------- status ---------- }

Procedure StatusSection(Const Title,Query:AnsiString;Const Kind:AnsiString);
Var
 L:TIList;
 I:LongInt;
 T:Int64;
 Repo:AnsiString;
Begin
 ApiPaged('/search/issues?q='+UrlEnc(Query,False)+'&sort=updated',10,'items',L,T);
 WriteLn(Title);
 If L.N=0 Then Begin WriteLn('  Nothing here ',#240#159#142#137);Exit;End;
 For I:=0 to L.N-1 do Begin
  Repo:=JS(L.A[I],'repository_url');
  Repo:=Copy(Repo,Pos('/repos/',Repo)+7,Length(Repo));
  WriteLn('  ',Repo,'#',JI(L.A[I],'number'),'  ',JS(L.A[I],'title'));
 End;
End;

Procedure CmdStatus;
Var
 L:TIList;
 I:LongInt;
 T:Int64;
 Repo:AnsiString;
 Org:AnsiString;
 Orgs:TSList;
Begin
 CmdBegin('status','');
 Opt('exclude','e','*strings','Comma separated list of repos to exclude in owner/name format@@Liste de d'+#130+'p'+#147+'ts '+#133+' exclure au format propri'+#130+'taire/nom');
 Opt('org','o','string','Report status within an organization (default: all organizations the authenticated user belongs to)@@Affiche l'''+#130+'tat dans une organisation');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 InitHostOpt;
 Org:='';
 If OptHas('org')Then Org:=' org:'+OptGet('org');
 StatusSection('Assigned Issues','is:open is:issue assignee:@me archived:false'+Org,'issue');
 WriteLn;
 StatusSection('Assigned Pull Requests','is:open is:pr assignee:@me archived:false'+Org,'pr');
 WriteLn;
 StatusSection('Review Requests','is:open is:pr review-requested:@me archived:false'+Org,'pr');
 WriteLn;
 StatusSection('Mentions','is:open mentions:@me archived:false'+Org,'issue');
 WriteLn;
 WriteLn('Repository Activity');
 ApiPaged('/notifications',10,'',L,T);
 If L.N=0 Then WriteLn('  Nothing here ',#240#159#142#137)
 Else For I:=0 to L.N-1 do Begin
  WriteLn('  ',JS(L.A[I],'repository.full_name'),': ',JS(L.A[I],'subject.title'));
 End;
End;

{ ---------- version, completion ---------- }

Procedure CmdVersion;
Begin
 CmdBegin('version','');
 ParseArgs(ArgStart);
 WriteLn('gh version ',ToolVersion,' (pascal)');
 WriteLn('https://github.com/cli/cli/releases/latest');
End;

Procedure ListSubs(Const Grp:AnsiString;Var L:TSList);
Var
 I:LongInt;
 P:AnsiString;
Begin
 SClear(L);
 For I:=0 to NDesc-1 do Begin
  P:=Descs[I].P;
  If Grp='' Then Begin
   If(Pos(' ',P)=0)Then SAdd(L,P);
  End
  Else If StartsWith(P,Grp+' ')and(Pos(' ',Copy(P,Length(Grp)+2,Length(P)))=0)Then
    SAdd(L,Copy(P,Length(Grp)+2,Length(P)));
 End;
End;

Function ExtractShell_:AnsiString;
Var
 S:AnsiString;
Begin
 S:=GetEnv('SHELL');
 If Pos('zsh',S)>0 Then ExtractShell_:='zsh'
 Else If Pos('fish',S)>0 Then ExtractShell_:='fish'
 Else ExtractShell_:='bash';
End;

Procedure CmdCompletion;
Var
 Sh:AnsiString;
 Tops,Subs:TSList;
 I:LongInt;
Begin
 CmdBegin('completion','-s <shell>');
 Opt('shell','s','string','Shell type: {bash|zsh|fish|powershell}@@Type de shell : {bash|zsh|fish|powershell}');
 CmdLong('Generate shell completion scripts for GitHub CLI commands.@@G'+#130+'n'+#138+'re les scripts d''autocompl'+#130+'tion de GitHub CLI.');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 Sh:=LoStr(OptGet('shell'));
 If Sh='' Then Begin
  {$IFDEF WINDOWS}
  Sh:='powershell';
  {$ELSE}
  Sh:=ExtractShell_;
  {$ENDIF}
 End;
 ListSubs('',Tops);
 SSort(Tops);
 If Sh='bash' Then Begin
  WriteLn('# bash completion for gh');
  WriteLn('_gh_complete() {');
  WriteLn('  local cur="${COMP_WORDS[COMP_CWORD]}"');
  WriteLn('  if [ "$COMP_CWORD" -eq 1 ]; then');
  WriteLn('    COMPREPLY=($(compgen -W "',JoinList(Tops,' '),' help" -- "$cur"))');
  WriteLn('    return');
  WriteLn('  fi');
  WriteLn('  case "${COMP_WORDS[1]}" in');
  For I:=0 to Tops.N-1 do Begin
   ListSubs(Tops.A[I],Subs);
   If Subs.N>0 Then Begin
    SSort(Subs);
    WriteLn('    ',Tops.A[I],') COMPREPLY=($(compgen -W "',JoinList(Subs,' '),'" -- "$cur")) ;;');
   End;
  End;
  WriteLn('  esac');
  WriteLn('}');
  WriteLn('complete -F _gh_complete gh');
 End
 Else If Sh='zsh' Then Begin
  WriteLn('#compdef gh');
  WriteLn('_gh() {');
  WriteLn('  local -a cmds');
  WriteLn('  if (( CURRENT == 2 )); then');
  Write('    cmds=(');
  For I:=0 to Tops.N-1 do Write('''',Tops.A[I],''' ');
  WriteLn(')');
  WriteLn('    _describe ''command'' cmds');
  WriteLn('    return');
  WriteLn('  fi');
  WriteLn('  case $words[2] in');
  For I:=0 to Tops.N-1 do Begin
   ListSubs(Tops.A[I],Subs);
   If Subs.N>0 Then Begin
    SSort(Subs);
    WriteLn('    ',Tops.A[I],') compadd ',JoinList(Subs,' '),' ;;');
   End;
  End;
  WriteLn('  esac');
  WriteLn('}');
  WriteLn('compdef _gh gh');
 End
 Else If Sh='fish' Then Begin
  WriteLn('# fish completion for gh');
  WriteLn('complete -c gh -f');
  WriteLn('complete -c gh -n "__fish_use_subcommand" -a "',JoinList(Tops,' '),'"');
  For I:=0 to Tops.N-1 do Begin
   ListSubs(Tops.A[I],Subs);
   If Subs.N>0 Then Begin
    SSort(Subs);
    WriteLn('complete -c gh -n "__fish_seen_subcommand_from ',Tops.A[I],'" -a "',JoinList(Subs,' '),'"');
   End;
  End;
 End
 Else If Sh='powershell' Then Begin
  WriteLn('Register-ArgumentCompleter -Native -CommandName ''gh'' -ScriptBlock {');
  WriteLn('  param($wordToComplete, $commandAst, $cursorPosition)');
  WriteLn('  $words = $commandAst.CommandElements | ForEach-Object { $_.ToString() }');
  WriteLn('  $map = @{');
  For I:=0 to Tops.N-1 do Begin
   ListSubs(Tops.A[I],Subs);
   If Subs.N>0 Then Begin
    SSort(Subs);
    WriteLn('    ''',Tops.A[I],''' = ''',JoinList(Subs,' '),'''');
   End;
  End;
  WriteLn('  }');
  WriteLn('  if ($words.Count -le 2) { ''',JoinList(Tops,' '),''' -split '' '' | Where-Object { $_ -like "$wordToComplete*" } }');
  WriteLn('  elseif ($map.ContainsKey($words[1])) { $map[$words[1]] -split '' '' | Where-Object { $_ -like "$wordToComplete*" } }');
  WriteLn('}');
 End
 Else Die2('error: unsupported shell type "'+Sh+'"',1);
End;

{ ------------------------------------------------------------------ }
{ gh repo, gh org                                                      }
{ ------------------------------------------------------------------ }

Const
 RepoFields='archivedAt,assignableUsers,codeOfConduct,contactLinks,createdAt,defaultBranchRef,deleteBranchOnMerge,'+
  'description,diskUsage,forkCount,fundingLinks,hasDiscussionsEnabled,hasIssuesEnabled,hasProjectsEnabled,'+
  'hasWikiEnabled,homepageUrl,id,isArchived,isBlankIssuesEnabled,isEmpty,isFork,isInOrganization,isMirror,isPrivate,'+
  'isSecurityPolicyEnabled,isTemplate,isUserConfigurationRepository,issueTemplates,issues,labels,languages,'+
  'latestRelease,licenseInfo,mentionableUsers,mergeCommitAllowed,milestones,mirrorUrl,name,nameWithOwner,'+
  'openGraphImageUrl,owner,parent,primaryLanguage,projects,projectsV2,pullRequestTemplates,pullRequests,pushedAt,'+
  'rebaseMergeAllowed,repositoryTopics,securityPolicyUrl,squashMergeAllowed,sshUrl,stargazerCount,templateRepository,'+
  'updatedAt,url,usesCustomOpenGraphImage,viewerCanAdminister,viewerDefaultCommitEmail,viewerDefaultMergeMethod,'+
  'viewerHasStarred,viewerPermission,viewerPossibleCommitEmails,viewerSubscription,visibility,watchers';
 RepoSpec='createdAt=created_at:s;description=description:s;diskUsage=size:n;forkCount=forks_count:n;'+
  'hasDiscussionsEnabled=has_discussions:b;hasIssuesEnabled=has_issues:b;hasProjectsEnabled=has_projects:b;'+
  'hasWikiEnabled=has_wiki:b;homepageUrl=homepage:s;id=node_id:s;isArchived=archived:b;isFork=fork:b;'+
  'isPrivate=private:b;isTemplate=is_template:b;mergeCommitAllowed=allow_merge_commit:b;name=name:s;'+
  'nameWithOwner=full_name:s;pushedAt=pushed_at:s;rebaseMergeAllowed=allow_rebase_merge:b;sshUrl=ssh_url:s;'+
  'squashMergeAllowed=allow_squash_merge:b;stargazerCount=stargazers_count:n;updatedAt=updated_at:s;url=html_url:s;'+
  'visibility=visibility:S;deleteBranchOnMerge=delete_branch_on_merge:b;mirrorUrl=mirror_url:N;archivedAt=archived_at:N';

Function RepoHook(Node:LongInt;Const F:AnsiString;Var Out_:AnsiString):Boolean;
Var
 L:TSList;
 P,I,C:LongInt;
 R:THttpReq;
 J:LongInt;
 Perm:AnsiString;
Begin
 RepoHook:=True;
 If F='defaultBranchRef' Then Begin
  If JS(Node,'default_branch')='' Then Out_:='null' Else Out_:='{"name":'+JQ(JS(Node,'default_branch'))+'}';
 End
 Else If F='licenseInfo' Then Begin
  P:=JGet(Node,'license');
  If(P<0)or(JP[P].Kind<>JK_OBJ)Then Out_:='null'
  Else Begin
   SClear(L);
   FS(L,'key',JS(P,'key'));FS(L,'name',JS(P,'name'));FS(L,'nickname','');FS(L,'spdxId',JS(P,'spdx_id'));
   FS(L,'url',JS(P,'url'));
   Out_:=ObjOf(L);
  End;
 End
 Else If F='owner' Then Begin
  SClear(L);
  FS(L,'id',JS(Node,'owner.node_id'));FS(L,'login',JS(Node,'owner.login'));
  Out_:=ObjOf(L);
 End
 Else If F='parent' Then Begin
  P:=JGet(Node,'parent');
  If(P<0)or(JP[P].Kind<>JK_OBJ)Then Out_:='null'
  Else Begin
   SClear(L);
   FS(L,'id',JS(P,'node_id'));FS(L,'name',JS(P,'name'));
   FR(L,'owner','{"id":'+JQ(JS(P,'owner.node_id'))+',"login":'+JQ(JS(P,'owner.login'))+'}');
   Out_:=ObjOf(L);
  End;
 End
 Else If F='primaryLanguage' Then Begin
  If JS(Node,'language')='' Then Out_:='null' Else Out_:='{"name":'+JQ(JS(Node,'language'))+'}';
 End
 Else If F='repositoryTopics' Then Begin
  SClear(L);
  P:=JGet(Node,'topics');
  If P>=0 Then Begin
   C:=JP[P].First;
   While C>=0 do Begin SAdd(L,'{"name":'+JQ(JTxt(C))+'}');C:=JP[C].Next;End;
  End;
  Out_:='['+JoinList(L,',')+']';
 End
 Else If F='watchers' Then Out_:='{"totalCount":'+IStr(JI(Node,'subscribers_count'))+'}'
 Else If F='issues' Then Out_:='{"totalCount":'+IStr(JI(Node,'open_issues_count'))+'}'
 Else If F='isEmpty' Then Out_:=JBool(JI(Node,'size')=0)
 Else If F='isMirror' Then Out_:=JBool(JS(Node,'mirror_url')<>'')
 Else If F='isInOrganization' Then Out_:=JBool(JS(Node,'owner.type')='Organization')
 Else If F='openGraphImageUrl' Then Out_:=JQ('https://opengraph.githubassets.com/'+JS(Node,'full_name'))
 Else If F='usesCustomOpenGraphImage' Then Out_:='false'
 Else If F='viewerCanAdminister' Then Out_:=JBool(JB(Node,'permissions.admin'))
 Else If F='viewerPermission' Then Begin
  If JB(Node,'permissions.admin')Then Perm:='ADMIN'
  Else If JB(Node,'permissions.maintain')Then Perm:='MAINTAIN'
  Else If JB(Node,'permissions.push')Then Perm:='WRITE'
  Else If JB(Node,'permissions.triage')Then Perm:='TRIAGE'
  Else Perm:='READ';
  Out_:=JQ(Perm);
 End
 Else If F='languages' Then Begin
  J:=ApiJ('GET','/repos/'+JS(Node,'full_name')+'/languages','');
  SClear(L);
  C:=JP[J].First;
  While C>=0 do Begin
   SAdd(L,'{"size":'+JP[C].S+',"node":{"name":'+JQ(JP[C].Key)+'}}');
   C:=JP[C].Next;
  End;
  Out_:='['+JoinList(L,',')+']';
 End
 Else If F='latestRelease' Then Begin
  ApiCall(R,'GET','/repos/'+JS(Node,'full_name')+'/releases/latest','');
  If ApiOk(R)Then Begin
   J:=JParse(R.RespBody);
   SClear(L);
   FS(L,'name',JS(J,'name'));FS(L,'tagName',JS(J,'tag_name'));FS(L,'url',JS(J,'html_url'));
   FS(L,'publishedAt',JS(J,'published_at'));
   Out_:=ObjOf(L);
  End
  Else Out_:='null';
 End
 Else If(F='viewerHasStarred')or(F='isSecurityPolicyEnabled')or(F='isBlankIssuesEnabled')or
   (F='isUserConfigurationRepository')Then Out_:='false'
 Else If(F='assignableUsers')or(F='mentionableUsers')or(F='labels')or(F='milestones')or(F='projects')or
   (F='projectsV2')or(F='pullRequests')or(F='issueTemplates')or(F='pullRequestTemplates')or(F='contactLinks')or
   (F='fundingLinks')or(F='viewerPossibleCommitEmails')Then Out_:='[]'
 Else If(F='codeOfConduct')or(F='templateRepository')or(F='securityPolicyUrl')or(F='viewerDefaultCommitEmail')or
   (F='viewerDefaultMergeMethod')or(F='viewerSubscription')Then Out_:='null'
 Else RepoHook:=False;
End;

{ nom [HOTE/]PROPRIETAIRE/DEPOT ou URL ; renseigne le depot courant }
Procedure UseRepoArg(Const S:AnsiString);
Var
 H,O,N:AnsiString;
Begin
 If S='' Then Begin NeedRepo;Exit;End;
 If not ParseRepoRef(S,H,O,N)Then Begin
  If Pos('/',S)=0 Then Begin
   InitHostOpt;
   O:=CurrentUser;N:=S;H:='';
  End
  Else Die('expected the "[HOST/]OWNER/REPO" format, got "'+S+'"');
 End;
 If H='' Then H:=DefaultHost;
 RepoHost:=H;RepoOwner:=O;RepoName:=N;RepoResolved:=True;
 ApiHost:=H;
End;

Function GetRepoNode:LongInt;
Begin
 GetRepoNode:=ApiJ('GET',RepoApi(''),'');
End;

Function RepoClonePath(Const Host,Owner,Name:AnsiString;SshProto:Boolean):AnsiString;
Begin
 If SshProto Then RepoClonePath:='git@'+GitHostName(Host)+':'+Owner+'/'+Name+'.git'
 Else RepoClonePath:=WebBaseOf(Host)+'/'+Owner+'/'+Name+'.git';
End;

Function GitProto(Const Host:AnsiString):Boolean;
Begin
 GitProto:=CfgGet('git_protocol',Host)='ssh';
End;

Function TopicsOf(Node:LongInt):TSList;
Var
 P,C:LongInt;
Begin
 SClear(TopicsOf);
 P:=JGet(Node,'topics');
 If P>=0 Then Begin
  C:=JP[P].First;
  While C>=0 do Begin SAdd(TopicsOf,JTxt(C));C:=JP[C].Next;End;
 End;
End;

{ ---------- repo list ---------- }

Procedure CmdRepoList;
Var
 Owner,Path,Lang,Vis,Topic:AnsiString;
 Lst,Keep:TIList;
 Limit,I,J,U:LongInt;
 Tot:Int64;
 Ok:Boolean;
 Tops:TSList;
 Hook:TFieldHook;
Begin
 CmdBegin('repo list','[<owner>]');
 CmdAlias('ls');
 Opt('archived','','','Show only archived repositories@@Affiche seulement les d'+#130+'p'+#147+'ts archiv'+#130+'s');
 Opt('fork','','','Show only forks@@Affiche seulement les forks');
 Opt('language','l','string','Filter by primary coding language@@Filtre par langage principal');
 OptLimitN('Maximum number of repositories to list',30);
 Opt('no-archived','','','Omit archived repositories@@Omet les d'+#130+'p'+#147+'ts archiv'+#130+'s');
 Opt('source','','','Show only non-forks@@Affiche seulement les d'+#130+'p'+#147+'ts qui ne sont pas des forks');
 Opt('topic','','*strings','Filter by topic@@Filtre par sujet');
 Opt('visibility','','string','Filter by repository visibility: {public|private|internal}@@Filtre par visibilit'+#130+' : {public|private|internal}');
 OptJsonAll;
 CmdJson(RepoFields);
 ParseArgs(ArgStart);
 NeedArgs(0,1);
 JsonSetup(RepoFields);
 Excl('fork','source');
 Excl('archived','no-archived');
 InitHostOpt;
 Limit:=OptInt('limit',30);
 If Limit<=0 Then Die2('invalid value for --limit: '+IStr(Limit),1);
 Owner:=Pos1(0);
 Lang:=LoStr(OptGet('language'));Vis:=LoStr(OptGet('visibility'));
 OptList('topic',Tops);
 If(Vis<>'')and(Vis<>'public')and(Vis<>'private')and(Vis<>'internal')Then
   Die2('invalid argument "'+Vis+'" for "--visibility" flag: valid values are {public|private|internal}',1);
 If Owner='' Then Path:='/user/repos?affiliation=owner&sort=pushed'
 Else Begin
  U:=ApiJ('GET','/users/'+PathEnc(Owner),'');
  If JS(U,'type')='Organization' Then Path:='/orgs/'+PathEnc(Owner)+'/repos?type=all&sort=pushed'
  Else If Owner=CurrentUser Then Path:='/user/repos?affiliation=owner&sort=pushed'
  Else Path:='/users/'+PathEnc(Owner)+'/repos?type=owner&sort=pushed';
 End;
 If(Owner='')Then Owner:=CurrentUser;
 If UseJson Then Hook:=@RepoHook Else Hook:=Nil;
 ApiPagedQ(Path,0,'',Lst);
 Keep.N:=0;
 For I:=0 to Lst.N-1 do Begin
  Ok:=True;
  If OptHas('archived')and not JB(Lst.A[I],'archived')Then Ok:=False;
  If OptHas('no-archived')and JB(Lst.A[I],'archived')Then Ok:=False;
  If OptHas('fork')and not JB(Lst.A[I],'fork')Then Ok:=False;
  If OptHas('source')and JB(Lst.A[I],'fork')Then Ok:=False;
  If(Lang<>'')and(LoStr(JS(Lst.A[I],'language'))<>Lang)Then Ok:=False;
  If(Vis<>'')and(LoStr(JS(Lst.A[I],'visibility'))<>Vis)Then Ok:=False;
  For J:=0 to Tops.N-1 do If SIndex(TopicsOf(Lst.A[I]),Tops.A[J])<0 Then Ok:=False;
  If Ok and(Keep.N<Limit)Then IAdd(Keep,Lst.A[I]);
 End;
 If UseJson Then Begin EmitItems(Keep,RepoSpec,Hook);Exit;End;
 If Keep.N=0 Then Begin
  WriteLn(StdErr,'No results match your search');
  Halt(1);
 End;
 ShowingLine(Keep.N,Keep.N,'repositories','@'+Owner);
 TblBegin('');
 For I:=0 to Keep.N-1 do Begin
  TblRow(JS(Keep.A[I],'full_name')+#9+JS(Keep.A[I],'description')+#9+
    IfThen_(JB(Keep.A[I],'archived'),LoStr(JS(Keep.A[I],'visibility'))+', archived',
    IfThen_(JB(Keep.A[I],'fork'),LoStr(JS(Keep.A[I],'visibility'))+', fork',LoStr(JS(Keep.A[I],'visibility'))))+
    #9+TimeCell(JS(Keep.A[I],'pushed_at')));
 End;
 TblPrint;
End;

{ ---------- repo view ---------- }

Procedure CmdRepoView;
Var
 J,I:LongInt;
 Readme:AnsiString;
 R:THttpReq;
 Br,Desc:AnsiString;
 Hook:TFieldHook;
Begin
 CmdBegin('repo view','[<repository>]');
 Opt('branch','b','string','View a specific branch of the repository@@Affiche une branche pr'+#130+'cise du d'+#130+'p'+#147+'t');
 OptJsonAll;
 OptWeb('Open a repository in the browser@@Ouvre un d'+#130+'p'+#147+'t dans le navigateur');
 CmdJson(RepoFields);
 ParseArgs(ArgStart);
 NeedArgs(0,1);
 JsonSetup(RepoFields);
 UseRepoArg(Pos1(0));
 If OptHas('web')Then Begin
  OpenWeb(RepoWebUrl+IfThen_(OptGet('branch')<>'','/tree/'+OptGet('branch'),''));
  Exit;
 End;
 J:=GetRepoNode;
 If UseJson Then Begin EmitItem(J,RepoSpec,@RepoHook);Exit;End;
 Br:=OptGet('branch');
 Readme:='';
 ReqInit(R,'GET',ApiUrl(RepoApi('/readme')+IfThen_(Br<>'','?ref='+UrlEnc(Br,False),'')),TokenOf(ApiHost));
 R.Headers:='Accept: application/vnd.github.raw'#13#10;
 HttpDo(R);
 If ApiOk(R)Then Readme:=R.RespBody;
 Desc:=JS(J,'description');
 If OutTTY Then Begin
  WriteLn(JS(J,'full_name'));
  If Desc<>'' Then WriteLn(Desc);
  WriteLn;
  If Readme<>'' Then Begin WriteLn(Readme);WriteLn;End
  Else WriteLn('This repository does not have a README');
  WriteLn('View this repository on GitHub: ',JS(J,'html_url'));
 End
 Else Begin
  WriteLn('name:'#9,JS(J,'full_name'));
  WriteLn('description:'#9,Desc);
  WriteLn('--');
  If Readme<>'' Then Write(Readme);
 End;
End;

{ ---------- repo create ---------- }

Procedure CmdRepoCreate;
Var
 Name,Owner,Vis,Tmpl,Body,Url,Src,Remote,O2_,N2_:AnsiString;
 F:TSList;
 J,I:LongInt;
 Pub,Priv,Int_:Boolean;
 H,O,N:AnsiString;
 R:THttpReq;
 Team:AnsiString;
 Opts:TSList;
Begin
 CmdBegin('repo create','[<name>]');
 Opt('add-readme','','','Add a README file to the new repository@@Ajoute un fichier README au nouveau d'+#130+'p'+#147+'t');
 Opt('clone','c','','Clone the new repository to the current directory@@Clone le nouveau d'+#130+'p'+#147+'t dans le r'+#130+'pertoire courant');
 Opt('description','d','string','Description of the repository@@Description du d'+#130+'p'+#147+'t');
 Opt('disable-issues','','','Disable issues in the new repository@@D'+#130+'sactive les tickets du nouveau d'+#130+'p'+#147+'t');
 Opt('disable-wiki','','','Disable wiki in the new repository@@D'+#130+'sactive le wiki du nouveau d'+#130+'p'+#147+'t');
 Opt('gitignore','g','string','Specify a gitignore template for the repository@@Mod'+#138+'le .gitignore du d'+#130+'p'+#147+'t');
 Opt('homepage','h','URL','Repository home page URL@@URL de la page d''accueil du d'+#130+'p'+#147+'t');
 Opt('include-all-branches','','','Include all branches from template repository@@Inclut toutes les branches du d'+#130+'p'+#147+'t mod'+#138+'le');
 Opt('internal','','','Make the new repository internal@@Rend le nouveau d'+#130+'p'+#147+'t interne');
 Opt('license','l','string','Specify an Open Source License for the repository@@Licence open source du d'+#130+'p'+#147+'t');
 Opt('private','','','Make the new repository private@@Rend le nouveau d'+#130+'p'+#147+'t priv'+#130+'');
 Opt('public','','','Make the new repository public@@Rend le nouveau d'+#130+'p'+#147+'t public');
 Opt('push','','','Push local commits to the new repository@@Envoie les commits locaux vers le nouveau d'+#130+'p'+#147+'t');
 Opt('remote','r','string','Specify remote name for the new repository@@Nom du remote du nouveau d'+#130+'p'+#147+'t');
 Opt('source','s','string','Specify path to local repository to use as source@@Chemin du d'+#130+'p'+#147+'t local '+#133+' utiliser comme source');
 Opt('team','t','name','The name of the organization team to be granted access@@'+#144+'quipe de l''organisation qui aura acc'+#138+'s');
 Opt('template','p','repository','Make the new repository based on a template repository@@Cr'+#130+'e le d'+#130+'p'+#147+'t '+#133+' partir d''un d'+#130+'p'+#147+'t mod'+#138+'le');
 CmdLong('Create a new GitHub repository.@@Cr'+#130+'e un nouveau d'+#130+'p'+#147+'t GitHub.');
 CmdExample('# create a repository interactively');
 CmdExample('$ gh repo create');
 CmdExample('# create a new remote repository and clone it locally');
 CmdExample('$ gh repo create my-project --public --clone');
 ParseArgs(ArgStart);
 NeedArgs(0,1);
 InitHostOpt;
 Pub:=OptHas('public');Priv:=OptHas('private');Int_:=OptHas('internal');
 If(Ord(Pub)+Ord(Priv)+Ord(Int_))>1 Then Die2('expected exactly one of `--public`, `--private`, or `--internal`',1);
 Name:=Pos1(0);
 If Name='' Then Begin
  If InteractiveOk Then Name:=AskLine('Repository name','')
  Else Die2('repository name required when not running interactively',1);
 End;
 If(Ord(Pub)+Ord(Priv)+Ord(Int_))=0 Then Begin
  If InteractiveOk Then Begin
   SClear(Opts);SAdd(Opts,'Public');SAdd(Opts,'Private');SAdd(Opts,'Internal');
   I:=AskSelect('Visibility',Opts);
   Pub:=I=0;Priv:=I=1;Int_:=I=2;
  End
  Else Die2('`--public`, `--private`, or `--internal` required when not running interactively',1);
 End;
 If Pos('/',Name)>0 Then Begin
  O:=Copy(Name,1,Pos('/',Name)-1);N:=Copy(Name,Pos('/',Name)+1,Length(Name));
 End
 Else Begin O:='';N:=Name;End;
 If Pub Then Vis:='public' Else If Priv Then Vis:='private' Else Vis:='internal';
 SClear(F);
 Tmpl:=OptGet('template');
 If Tmpl<>'' Then Begin
  If not ParseRepoRef(Tmpl,H,O2_,N2_)Then Die('invalid template repository '+Tmpl);
  If O='' Then O:=CurrentUser;
  FS(F,'owner',O);FS(F,'name',N);FS(F,'description',OptGet('description'));
  FB(F,'private',Vis<>'public');
  If OptHas('include-all-branches')Then FB(F,'include_all_branches',True);
  J:=ApiJ('POST','/repos/'+O2_+'/'+N2_+'/generate',ObjOf(F));
 End
 Else Begin
  FS(F,'name',N);
  If OptHas('description')Then FS(F,'description',OptGet('description'));
  If OptHas('homepage')Then FS(F,'homepage',OptGet('homepage'));
  If Vis='internal' Then FS(F,'visibility','internal') Else FB(F,'private',Vis='private');
  If OptHas('disable-issues')Then FB(F,'has_issues',False);
  If OptHas('disable-wiki')Then FB(F,'has_wiki',False);
  If OptHas('add-readme')Then FB(F,'auto_init',True);
  If OptHas('gitignore')Then FS(F,'gitignore_template',OptGet('gitignore'));
  If OptHas('license')Then FS(F,'license_template',OptGet('license'));
  If OptHas('team')Then Begin
   Team:=OptGet('team');
   If O='' Then Die('the --team option is only supported for organization repositories');
   FN(F,'team_id',JI(ApiJ('GET','/orgs/'+PathEnc(O)+'/teams/'+PathEnc(Team),''),'id'));
  End;
  If(O<>'')and(O<>CurrentUser)Then J:=ApiJ('POST','/orgs/'+PathEnc(O)+'/repos',ObjOf(F))
  Else J:=ApiJ('POST','/user/repos',ObjOf(F));
 End;
 Url:=JS(J,'html_url');
 WriteLn(Url);
 If ErrTTY Then WriteLn(StdErr,#226#156#147' Created repository ',JS(J,'full_name'),' on ',GitHostName(ApiHost));
 Src:=OptGet('source');
 If Src<>'' Then Begin
  Remote:=OptGet('remote');If Remote='' Then Remote:='origin';
  If GitFg('-C '+Q(Src)+' remote add '+Remote+' '+Q(RepoClonePath(ApiHost,JS(J,'owner.login'),JS(J,'name'),GitProto(ApiHost))))<>0 Then
    Die('could not add remote');
  WriteLn(StdErr,#226#156#147' Added remote ',Remote);
  If OptHas('push')Then GitFg('-C '+Q(Src)+' push --set-upstream '+Remote+' HEAD');
 End
 Else If OptHas('clone')Then Begin
  GitFg('clone '+Q(RepoClonePath(ApiHost,JS(J,'owner.login'),JS(J,'name'),GitProto(ApiHost))));
 End;
End;

{ ---------- repo clone ---------- }

Procedure CmdRepoClone;
Var
 J,P:LongInt;
 Spec,Dir,Extra,Url,Up:AnsiString;
 I,K:LongInt;
 Args:TSList;
 Git:AnsiString;
Begin
 CmdBegin('repo clone','<repository> [<directory>] [-- <gitflags>...]');
 Opt('upstream-remote-name','u','string','Upstream remote name when cloning a fork@@Nom du remote amont lors du clonage d''un fork');
 CmdLong('Clone a GitHub repository locally.@@Clone un d'+#130+'p'+#147+'t GitHub localement.');
 CmdExample('$ gh repo clone cli/cli');
 CmdExample('$ gh repo clone cli/cli cli-copy');
 ParseArgs(ArgStart);
 NeedArgs(1,-1);
 Spec:=Pos1(0);
 Dir:='';Extra:='';
 K:=1;
 If(PosArgs.N>1)Then Begin Dir:=PosArgs.A[1];K:=2;End;
 For I:=K to PosArgs.N-1 do Extra:=Extra+' '+Q(PosArgs.A[I]);
 If StartsWith(Spec,'git@')or StartsWith(Spec,'ssh://')Then Url:=Spec;
 UseRepoArg(Spec);
 If (Url='')Then Begin
  Url:=RepoClonePath(RepoHost,RepoOwner,RepoName,GitProto(RepoHost));
  If StartsWith(Spec,'http://')or StartsWith(Spec,'https://')Then Url:=Spec;
 End;
 J:=GetRepoNode;
 Git:='clone '+Q(Url)+IfThen_(Dir<>'',' '+Q(Dir),'')+Extra;
 If GitFg(Git)<>0 Then Halt(GitRC);
 If JB(J,'fork')Then Begin
  P:=JGet(J,'parent');
  If P>=0 Then Begin
   Up:=OptGet('upstream-remote-name');If Up='' Then Up:='upstream';
   If Dir='' Then Dir:=RepoName;
   Url:=RepoClonePath(RepoHost,JS(P,'owner.login'),JS(P,'name'),GitProto(RepoHost));
   GitFg('-C '+Q(Dir)+' remote add -f '+Up+' '+Q(Url));
   GitFg('-C '+Q(Dir)+' config --add remote.'+Up+'.gh-resolved base');
   GitFg('-C '+Q(Dir)+' config --unset-all remote.origin.gh-resolved');
  End;
 End;
End;

{ ---------- repo fork ---------- }

Procedure CmdRepoFork;
Var
 J,P:LongInt;
 F:TSList;
 Org,Nm,Url,Rn:AnsiString;
 Fork:Boolean;
Begin
 CmdBegin('repo fork','[<repository>] [-- <gitflags>...]');
 Opt('clone','','','Clone the fork@@Clone le fork');
 Opt('default-branch-only','','','Only include the default branch in the fork@@Inclut seulement la branche par d'+#130+'faut dans le fork');
 Opt('fork-name','','string','Rename the forked repository@@Renomme le d'+#130+'p'+#147+'t d'+#130+'riv'+#130+'');
 Opt('org','','string','Create the fork in an organization@@Cr'+#130+'e le fork dans une organisation');
 Opt('remote','','','Add a git remote for the fork@@Ajoute un remote git pour le fork');
 Opt('remote-name','','string','Specify the name for the new remote@@Nom du nouveau remote');
 CmdLong('Create a fork of a repository.@@Cr'+#130+'e une copie d'+#130+'riv'+#130+'e (fork) d''un d'+#130+'p'+#147+'t.');
 ParseArgs(ArgStart);
 NeedArgs(0,-1);
 UseRepoArg(Pos1(0));
 SClear(F);
 If OptHas('org')Then FS(F,'organization',OptGet('org'));
 If OptHas('fork-name')Then FS(F,'name',OptGet('fork-name'));
 If OptHas('default-branch-only')Then FB(F,'default_branch_only',True);
 J:=ApiJ('POST',RepoApi('/forks'),ObjOf(F));
 WriteLn(StdErr,#226#156#147' Created fork ',JS(J,'full_name'));
 Rn:=OptGet('remote-name');
 If Rn='' Then Rn:='origin';
 Url:=RepoClonePath(ApiHost,JS(J,'owner.login'),JS(J,'name'),GitProto(ApiHost));
 If OptHas('clone')Then Begin
  GitFg('clone '+Q(Url));
  GitFg('-C '+Q(JS(J,'name'))+' remote add -f upstream '+Q(RepoClonePath(ApiHost,RepoOwner,RepoName,GitProto(ApiHost))));
  GitFg('-C '+Q(JS(J,'name'))+' config --add remote.upstream.gh-resolved base');
 End
 Else If OptHas('remote')and InGitRepo Then Begin
  If Rn='origin' Then GitFg('remote rename origin upstream');
  GitFg('remote add '+Rn+' '+Q(Url));
  WriteLn(StdErr,#226#156#147' Added remote ',Rn);
 End;
 WriteLn(JS(J,'html_url'));
End;

{ ---------- repo edit ---------- }

Procedure CmdRepoEdit;
Var
 F:TSList;
 J:LongInt;
 Topics,Add,Rem:TSList;
 I,K:LongInt;
 Cur:LongInt;
 Sec:TSList;
 V:AnsiString;
 Procedure BoolOpt(Const Name,Key:AnsiString);
 Begin
  If OptHas(Name)Then Begin
   V:=LoStr(OptGet(Name));
   If(V='')or(V='true')Then FB(F,Key,True) Else FB(F,Key,False);
  End;
 End;
Begin
 CmdBegin('repo edit','[<repository>]');
 Opt('accept-visibility-change-consequences','','','Accept the consequences of changing the repository visibility@@Accepte les cons'+#130+'quences du changement de visibilit'+#130+'');
 Opt('add-topic','','*strings','Add repository topic@@Ajoute un sujet au d'+#130+'p'+#147+'t');
 Opt('allow-forking','','','Allow forking of an organization repository@@Autorise le fork d''un d'+#130+'p'+#147+'t d''organisation');
 Opt('allow-update-branch','','','Allow a pull request head branch that is behind its base branch to be updated@@Autorise la mise '+#133+' jour des branches en retard');
 Opt('default-branch','','name','Set the default branch name for the repository@@D'+#130+'finit la branche par d'+#130+'faut');
 Opt('delete-branch-on-merge','','','Delete head branch when pull requests are merged@@Supprime la branche source apr'+#138+'s fusion');
 Opt('description','d','string','Description of the repository@@Description du d'+#130+'p'+#147+'t');
 Opt('enable-auto-merge','','','Enable auto-merge functionality@@Active la fusion automatique');
 Opt('enable-discussions','','','Enable discussions in the repository@@Active les discussions');
 Opt('enable-issues','','','Enable issues in the repository@@Active les tickets');
 Opt('enable-merge-commit','','','Enable merging pull requests via merge commit@@Active la fusion par commit de fusion');
 Opt('enable-projects','','','Enable projects in the repository@@Active les projets');
 Opt('enable-rebase-merge','','','Enable merging pull requests via rebase@@Active la fusion par rebase');
 Opt('enable-squash-merge','','','Enable merging pull requests via squashed commit@@Active la fusion par '+#130+'crasement (squash)');
 Opt('enable-wiki','','','Enable wiki in the repository@@Active le wiki');
 Opt('homepage','h','URL','Repository home page URL@@URL de la page d''accueil du d'+#130+'p'+#147+'t');
 Opt('remove-topic','','*strings','Remove repository topic@@Retire un sujet du d'+#130+'p'+#147+'t');
 Opt('template','','','Make the repository available as a template repository@@Rend le d'+#130+'p'+#147+'t disponible comme mod'+#138+'le');
 Opt('visibility','','string','Change the visibility of the repository to {public,private,internal}@@Change la visibilit'+#130+' du d'+#130+'p'+#147+'t : {public,private,internal}');
 CmdLong('Edit repository settings.@@Modifie les param'+#138+'tres d''un d'+#130+'p'+#147+'t.');
 ParseArgs(ArgStart);
 NeedArgs(0,1);
 UseRepoArg(Pos1(0));
 SClear(F);
 If OptHas('description')Then FS(F,'description',OptGet('description'));
 If OptHas('homepage')Then FS(F,'homepage',OptGet('homepage'));
 If OptHas('default-branch')Then FS(F,'default_branch',OptGet('default-branch'));
 If OptHas('visibility')Then Begin
  V:=LoStr(OptGet('visibility'));
  If(V<>'public')and(V<>'private')and(V<>'internal')Then
    Die2('invalid argument "'+V+'" for "--visibility" flag: valid values are {public|private|internal}',1);
  If not OptHas('accept-visibility-change-consequences')Then
    Die2('use of --visibility flag requires --accept-visibility-change-consequences flag',1);
  FS(F,'visibility',V);
 End;
 BoolOpt('enable-issues','has_issues');BoolOpt('enable-projects','has_projects');BoolOpt('enable-wiki','has_wiki');
 BoolOpt('enable-discussions','has_discussions');BoolOpt('enable-merge-commit','allow_merge_commit');
 BoolOpt('enable-squash-merge','allow_squash_merge');BoolOpt('enable-rebase-merge','allow_rebase_merge');
 BoolOpt('enable-auto-merge','allow_auto_merge');BoolOpt('delete-branch-on-merge','delete_branch_on_merge');
 BoolOpt('allow-update-branch','allow_update_branch');BoolOpt('allow-forking','allow_forking');
 BoolOpt('template','is_template');
 OptCsv('add-topic',Add);OptCsv('remove-topic',Rem);
 If(F.N=0)and(Add.N=0)and(Rem.N=0)Then Die2('specify properties to edit',1);
 If F.N>0 Then ApiJ('PATCH',RepoApi(''),ObjOf(F));
 If(Add.N>0)or(Rem.N>0)Then Begin
  J:=ApiJ('GET',RepoApi('/topics'),'');
  SClear(Topics);
  Cur:=JGet(J,'names');
  If Cur>=0 Then Begin K:=JP[Cur].First;While K>=0 do Begin SAdd(Topics,JTxt(K));K:=JP[K].Next;End;End;
  For I:=0 to Add.N-1 do If SIndex(Topics,Add.A[I])<0 Then SAdd(Topics,Add.A[I]);
  SClear(Sec);
  For I:=0 to Topics.N-1 do If SIndex(Rem,Topics.A[I])<0 Then SAdd(Sec,Topics.A[I]);
  ApiJ('PUT',RepoApi('/topics'),'{"names":'+StrArr(Sec)+'}');
 End;
 WriteLn(StdErr,#226#156#147' Edited repository ',RepoFull);
End;

{ ---------- repo delete / archive / rename ---------- }

Procedure ConfirmRepo(Const Prompt_:AnsiString);
Var
 T:AnsiString;
Begin
 If OptHas('yes')Then Exit;
 If not InteractiveOk Then Die2('--yes required when not running interactively',1);
 T:=AskLine(Prompt_,'');
 If T<>RepoFull Then Begin WriteLn(StdErr,'Cancelled.');Halt(2);End;
End;

Procedure CmdRepoDelete;
Begin
 CmdBegin('repo delete','[<repository>]');
 Opt('yes','','','Confirm deletion without prompting@@Confirme la suppression sans demander');
 CmdLong('Delete a GitHub repository.@@Supprime un d'+#130+'p'+#147+'t GitHub.');
 ParseArgs(ArgStart);
 NeedArgs(0,1);
 If Pos1(0)='' Then Die2('argument required to prevent accidental deletion',1);
 UseRepoArg(Pos1(0));
 ConfirmRepo('Type '+RepoFull+' to confirm deletion:');
 ApiJ('DELETE',RepoApi(''),'');
 WriteLn(StdErr,#226#156#147' Deleted repository ',RepoFull);
End;

Procedure RepoArchive(Value:Boolean);
Var
 J:LongInt;
Begin
 If Value Then CmdBegin('repo archive','[<repository>]') Else CmdBegin('repo unarchive','[<repository>]');
 Opt('yes','y','','Skip the confirmation prompt@@N''affiche pas la confirmation');
 ParseArgs(ArgStart);
 NeedArgs(0,1);
 UseRepoArg(Pos1(0));
 J:=GetRepoNode;
 If JB(J,'archived')=Value Then Begin
  WriteLn(StdErr,'! Repository ',RepoFull,' is already ',IfThen_(Value,'archived','not archived'));
  Exit;
 End;
 If not OptHas('yes')Then Begin
  If not InteractiveOk Then Die2('--yes required when not running interactively',1);
  If not Confirm('Archive '+RepoFull+'?',False)Then Begin WriteLn(StdErr,'Cancelled.');Halt(2);End;
 End;
 ApiJ('PATCH',RepoApi(''),'{"archived":'+JBool(Value)+'}');
 WriteLn(StdErr,#226#156#147' ',IfThen_(Value,'Archived','Unarchived'),' repository ',RepoFull);
End;

Procedure CmdRepoArchive;
Begin
 RepoArchive(True);
End;

Procedure CmdRepoUnarchive;
Begin
 RepoArchive(False);
End;

Procedure CmdRepoRename;
Var
 NewName:AnsiString;
 J,I:LongInt;
Begin
 CmdBegin('repo rename','[<new-name>]');
 OptRepo;
 Opt('yes','y','','Skip the confirmation prompt@@N''affiche pas la confirmation');
 ParseArgs(ArgStart);
 NeedArgs(0,1);
 NeedRepo;
 NewName:=Pos1(0);
 If NewName='' Then Begin
  If InteractiveOk Then NewName:=AskLine('New repository name','')
  Else Die2('new name argument required when not running interactively',1);
 End;
 If Pos('/',NewName)>0 Then NewName:=Copy(NewName,Pos('/',NewName)+1,Length(NewName));
 If not OptHas('yes')and InteractiveOk Then
   If not Confirm('Rename '+RepoFull+' to '+NewName+'?',False)Then Begin WriteLn(StdErr,'Cancelled.');Halt(2);End;
 J:=ApiJ('PATCH',RepoApi(''),'{"name":'+JQ(NewName)+'}');
 WriteLn(StdErr,#226#156#147' Renamed repository ',JS(J,'full_name'));
 If InGitRepo and not OptHas('repo')Then Begin
  I:=BaseRemote;
  If I>=0 Then GitFg('remote set-url '+Remotes[I].Name+' '+Q(RepoClonePath(ApiHost,JS(J,'owner.login'),JS(J,'name'),GitProto(ApiHost))));
 End;
End;

{ ---------- repo sync, set-default ---------- }

Procedure CmdRepoSync;
Var
 Br,Src:AnsiString;
 J:LongInt;
 F:TSList;
 Local:Boolean;
Begin
 CmdBegin('repo sync','[<destination-repository>]');
 Opt('branch','b','string','Branch to sync (default: default branch)@@Branche '+#133+' synchroniser (d'+#130+'faut : branche par d'+#130+'faut)');
 Opt('force','','','Hard reset the branch of the destination repository to match the source repository@@Force la branche de destination '+#133+' correspondre '+#133+' la source');
 Opt('source','s','string','Source repository@@D'+#130+'p'+#147+'t source');
 CmdLong('Sync destination repository from source repository.@@Synchronise le d'+#130+'p'+#147+'t de destination depuis le d'+#130+'p'+#147+'t source.');
 ParseArgs(ArgStart);
 NeedArgs(0,1);
 Local:=Pos1(0)='';
 UseRepoArg(Pos1(0));
 J:=GetRepoNode;
 Br:=OptGet('branch');
 If Br='' Then Br:=JS(J,'default_branch');
 If OptHas('source')Then Begin
  Src:=OptGet('source');
  Die('syncing from an arbitrary source is not supported by this clone; the parent repository is used');
 End;
 If not JB(J,'fork')Then Die('can''t sync because '+RepoFull+' is not a fork');
 SClear(F);
 FS(F,'branch',Br);
 ApiJ('POST',RepoApi('/merge-upstream'),ObjOf(F));
 WriteLn(StdErr,#226#156#147' Synced the "',Br,'" branch from ',JS(J,'parent.full_name'),' to ',RepoFull);
 If Local and InGitRepo Then Begin
  GitFg('fetch origin '+Br);
  If GitOut('rev-parse --abbrev-ref HEAD')=Br Then GitFg('merge --ff-only origin/'+Br);
 End;
End;

Procedure CmdRepoSetDefault;
Var
 I:LongInt;
 Sel:AnsiString;
 H,O,N:AnsiString;
Begin
 CmdBegin('repo set-default','[<repository>]');
 Opt('unset','u','','Unset the current default repository@@Retire le d'+#130+'p'+#147+'t par d'+#130+'faut');
 Opt('view','v','','View the current default repository@@Affiche le d'+#130+'p'+#147+'t par d'+#130+'faut');
 ParseArgs(ArgStart);
 NeedArgs(0,1);
 If not InGitRepo Then Die('repo set-default: not a git repository');
 LoadRemotes;
 If OptHas('view')Then Begin
  For I:=0 to NRemotes-1 do If Remotes[I].Resolved='base' Then Begin
   ParseRepoRef(Remotes[I].Url,H,O,N);
   WriteLn(O,'/',N);
   Exit;
  End;
  WriteLn(StdErr,'no default repository has been set; use `gh repo set-default` to select one');
  Exit;
 End;
 If OptHas('unset')Then Begin
  For I:=0 to NRemotes-1 do If Remotes[I].Resolved<>'' Then
    GitFg('config --unset-all remote.'+Remotes[I].Name+'.gh-resolved');
  Exit;
 End;
 Sel:=Pos1(0);
 If Sel='' Then Begin
  If NRemotes=1 Then Sel:='' Else Die('please specify a repository: gh repo set-default OWNER/REPO');
 End;
 For I:=0 to NRemotes-1 do Begin
  If ParseRepoRef(Remotes[I].Url,H,O,N)and((Sel='')or(Sel=O+'/'+N))Then Begin
   GitFg('config --unset-all remote.'+Remotes[I].Name+'.gh-resolved');
   GitFg('config --add remote.'+Remotes[I].Name+'.gh-resolved base');
   WriteLn(StdErr,#226#156#147' Set ',O,'/',N,' as the default repository for the current directory');
   Exit;
  End;
 End;
 Die('no matching git remote found for '+Sel);
End;

{ ---------- deploy-key, gitignore, license, autolink ---------- }

Procedure CmdDeployKeyList;
Var
 L:TIList;
 I:LongInt;
 Spec:AnsiString;
Begin
 CmdBegin('repo deploy-key list','');
 CmdAlias('ls');
 OptRepo;OptJsonAll;
 CmdJson('id,key,title,createdAt,readOnly');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 JsonSetup('id,key,title,createdAt,readOnly');
 NeedRepo;
 ApiPagedQ(RepoApi('/keys'),0,'',L);
 If UseJson Then Begin
  Spec:='id=id:n;key=key:s;title=title:s;createdAt=created_at:s;readOnly=read_only:b';
  EmitItems(L,Spec,Nil);Exit;
 End;
 If L.N=0 Then Begin WriteLn(StdErr,'No deploy keys found in ',RepoFull);Halt(1);End;
 TblBegin('ID'#9'TITLE'#9'TYPE'#9'KEY'#9'CREATED AT');
 For I:=0 to L.N-1 do
  TblRow(IStr(JI(L.A[I],'id'))+#9+JS(L.A[I],'title')+#9+IfThen_(JB(L.A[I],'read_only'),'read-only','read-write')+#9+
    Trunc_(JS(L.A[I],'key'),50)+#9+TimeCell(JS(L.A[I],'created_at')));
 TblPrint;
End;

Procedure CmdDeployKeyAdd;
Var
 Txt:AnsiString;
 F:TSList;
 J:LongInt;
Begin
 CmdBegin('repo deploy-key add','<key-file>');
 OptRepo;
 Opt('allow-write','w','','Allow write access for the key@@Autorise l''acc'+#138+'s en '+#130+'criture pour la cl'+#130+'');
 Opt('title','t','string','Title of the new key@@Titre de la nouvelle cl'+#130+'');
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 NeedRepo;
 If Pos1(0)='-' Then Txt:=ReadStdin
 Else If not ReadAll(Pos1(0),Txt)Then Die('open '+Pos1(0)+': no such file or directory');
 SClear(F);
 FS(F,'title',OptGet('title'));FS(F,'key',TrimStr(Txt));FB(F,'read_only',not OptHas('allow-write'));
 J:=ApiJ('POST',RepoApi('/keys'),ObjOf(F));
 WriteLn(StdErr,#226#156#147' Deploy key added to ',RepoFull);
End;

Procedure CmdDeployKeyDelete;
Begin
 CmdBegin('repo deploy-key delete','<key-id>');
 OptRepo;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 NeedRepo;
 ApiJ('DELETE',RepoApi('/keys/'+IStr(ToInt(Pos1(0),0))),'');
 WriteLn(StdErr,#226#156#147' Deploy key deleted from ',RepoFull);
End;

Procedure CmdGitignoreList;
Var
 J,C:LongInt;
Begin
 CmdBegin('repo gitignore list','');
 CmdAlias('ls');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 InitHostOpt;
 J:=ApiJ('GET','/gitignore/templates','');
 If OutTTY Then WriteLn('GITIGNORE TEMPLATE NAME');
 C:=JP[J].First;
 While C>=0 do Begin WriteLn(JTxt(C));C:=JP[C].Next;End;
End;

Procedure CmdGitignoreView;
Var
 J:LongInt;
Begin
 CmdBegin('repo gitignore view','<template>');
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 InitHostOpt;
 J:=ApiJ('GET','/gitignore/templates/'+PathEnc(Pos1(0)),'');
 Write(JS(J,'source'));
End;

Procedure CmdLicenseList;
Var
 L:TIList;
 I:LongInt;
 J:LongInt;
Begin
 CmdBegin('repo license list','');
 CmdAlias('ls');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 InitHostOpt;
 J:=ApiJ('GET','/licenses','');
 TblBegin('LICENSE KEY'#9'SPDX ID'#9'LICENSE NAME');
 I:=JP[J].First;
 While I>=0 do Begin
  TblRow(JS(I,'key')+#9+JS(I,'spdx_id')+#9+JS(I,'name'));
  I:=JP[I].Next;
 End;
 TblPrint;
End;

Procedure CmdLicenseView;
Var
 J:LongInt;
Begin
 CmdBegin('repo license view','{<license-key> | <spdx-id>}');
 OptWeb('Open https://choosealicense.com/ in the browser@@Ouvre https://choosealicense.com/ dans le navigateur');
 ParseArgs(ArgStart);
 NeedArgs(0,1);
 InitHostOpt;
 If OptHas('web')Then Begin OpenWeb('https://choosealicense.com/licenses/'+LoStr(Pos1(0)));Exit;End;
 If Pos1(0)='' Then Begin
  NeedRepo;
  J:=ApiJ('GET',RepoApi('/license'),'');
  Write(JS(J,'license.body'));
  Exit;
 End;
 J:=ApiJ('GET','/licenses/'+PathEnc(LoStr(Pos1(0))),'');
 If OutTTY Then Begin
  WriteLn(JS(J,'name'));
  WriteLn(JS(J,'description'));
  WriteLn;
 End;
 Write(JS(J,'body'));
End;

Procedure CmdAutolinkList;
Var
 L:TIList;
 I:LongInt;
 Spec:AnsiString;
Begin
 CmdBegin('repo autolink list','');
 CmdAlias('ls');
 OptRepo;OptJsonAll;OptWeb('List autolink references in the web browser@@Liste les r'+#130+'f'+#130+'rences dans le navigateur');
 CmdJson('id,isAlphanumeric,keyPrefix,urlTemplate');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 JsonSetup('id,isAlphanumeric,keyPrefix,urlTemplate');
 NeedRepo;
 If OptHas('web')Then Begin OpenWeb(RepoWebUrl+'/settings/key_links');Exit;End;
 ApiPagedQ(RepoApi('/autolinks'),0,'',L);
 If UseJson Then Begin
  Spec:='id=id:n;isAlphanumeric=is_alphanumeric:b;keyPrefix=key_prefix:s;urlTemplate=url_template:s';
  EmitItems(L,Spec,Nil);Exit;
 End;
 If L.N=0 Then Begin WriteLn(StdErr,'no autolinks found in ',RepoFull);Halt(1);End;
 TblBegin('ID'#9'KEY PREFIX'#9'URL TEMPLATE'#9'ALPHANUMERIC');
 For I:=0 to L.N-1 do
  TblRow(IStr(JI(L.A[I],'id'))+#9+JS(L.A[I],'key_prefix')+#9+JS(L.A[I],'url_template')+#9+
    JBool(JB(L.A[I],'is_alphanumeric')));
 TblPrint;
End;

Procedure CmdAutolinkCreate;
Var
 F:TSList;
 J:LongInt;
Begin
 CmdBegin('repo autolink create','<keyPrefix> <urlTemplate>');
 OptRepo;
 Opt('numeric','n','','Mark autolink as numeric@@Marque l''autolink comme num'+#130+'rique');
 ParseArgs(ArgStart);
 NeedArgs(2,2);
 NeedRepo;
 SClear(F);
 FS(F,'key_prefix',Pos1(0));FS(F,'url_template',Pos1(1));FB(F,'is_alphanumeric',not OptHas('numeric'));
 J:=ApiJ('POST',RepoApi('/autolinks'),ObjOf(F));
 WriteLn(StdErr,#226#156#147' Created repository autolink ',JI(J,'id'),' on ',RepoFull);
End;

Procedure CmdAutolinkView;
Var
 J:LongInt;
Begin
 CmdBegin('repo autolink view','<id>');
 OptRepo;OptJsonAll;
 CmdJson('id,isAlphanumeric,keyPrefix,urlTemplate');
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 JsonSetup('id,isAlphanumeric,keyPrefix,urlTemplate');
 NeedRepo;
 J:=ApiJ('GET',RepoApi('/autolinks/'+IStr(ToInt(Pos1(0),0))),'');
 If UseJson Then Begin
  EmitItem(J,'id=id:n;isAlphanumeric=is_alphanumeric:b;keyPrefix=key_prefix:s;urlTemplate=url_template:s',Nil);Exit;
 End;
 WriteLn('Autolink in ',RepoFull);
 WriteLn;
 WriteLn('ID: ',JI(J,'id'));
 WriteLn('Key Prefix: ',JS(J,'key_prefix'));
 WriteLn('URL Template: ',JS(J,'url_template'));
 WriteLn('Alphanumeric: ',JBool(JB(J,'is_alphanumeric')));
End;

Procedure CmdAutolinkDelete;
Begin
 CmdBegin('repo autolink delete','<id>');
 OptRepo;
 Opt('yes','y','','Confirm deletion without prompting@@Confirme la suppression sans demander');
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 NeedRepo;
 If not OptHas('yes')and InteractiveOk Then
   If not Confirm('Delete autolink '+Pos1(0)+' in '+RepoFull+'?',False)Then Halt(2);
 ApiJ('DELETE',RepoApi('/autolinks/'+IStr(ToInt(Pos1(0),0))),'');
 WriteLn(StdErr,#226#156#147' Autolink ',Pos1(0),' deleted from ',RepoFull);
End;

{ ---------- org list ---------- }

Procedure CmdOrgList;
Var
 L:TIList;
 I,Lim:LongInt;
Begin
 CmdBegin('org list','');
 CmdAlias('ls');
 OptLimitN('Maximum number of organizations to list',30);
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 InitHostOpt;
 Lim:=OptInt('limit',30);
 ApiPagedQ('/user/orgs',Lim,'',L);
 If L.N=0 Then Begin WriteLn(StdErr,'You are not a member of any organizations');Halt(1);End;
 ShowingLine(L.N,L.N,'organizations','@'+CurrentUser);
 For I:=0 to L.N-1 do WriteLn(JS(L.A[I],'login'));
End;
{ ------------------------------------------------------------------ }
{ Aide generale, sujets d'aide, distribution des commandes             }
{ ------------------------------------------------------------------ }

Type
 TProc = Procedure;
 TDisp = Record
  P:AnsiString;
  F:TProc;
 End;

Procedure PrintGroupHelp(Const Path:AnsiString);
Var
 I,W:LongInt;
 Subs:TSList;
 P:AnsiString;
Begin
 WriteLn(DescOf(Path));
 WriteLn;
 WriteLn(Lg('USAGE','UTILISATION'));
 WriteLn('  gh ',Path,' <',Lg('command','commande'),'> [flags]');
 WriteLn;
 ListSubs(Path,Subs);
 SSort(Subs);
 WriteLn(Lg('AVAILABLE COMMANDS','COMMANDES DISPONIBLES'));
 W:=0;
 For I:=0 to Subs.N-1 do If Length(Subs.A[I])>W Then W:=Length(Subs.A[I]);
 For I:=0 to Subs.N-1 do
  WriteLn('  ',PadR(Subs.A[I]+':',W+1),'  ',DescOf(Path+' '+Subs.A[I]));
 WriteLn;
 WriteLn(Lg('INHERITED FLAGS','OPTIONS H'+#144+'RIT'+#144+'ES'));
 WriteLn('      --help                     ',Lg('Show help for command','Affiche l''aide de la commande'));
 If(Path<>'config')and(Path<>'alias')and(Path<>'auth')and(Path<>'extension')and(Path<>'completion')Then
  WriteLn('  -R, --repo [HOST/]OWNER/REPO   ',Lg('Select another repository using the [HOST/]OWNER/REPO format',
    'S'+#130+'lectionne un autre d'+#130+'p'+#147+'t au format [H'+#195+#148+'TE/]PROPRI'+#144+'TAIRE/D'+#144+'P'+#195+#148+'T'));
 WriteLn;
 WriteLn(Lg('LEARN MORE','EN SAVOIR PLUS'));
 WriteLn('  ',Lg('Use `gh <command> <subcommand> --help` for more information about a command.',
   'Utilisez `gh <commande> <sous-commande> --help` pour plus d''informations sur une commande.'));
 WriteLn('  ',Lg('Read the manual at https://cli.github.com/manual','Lisez le manuel '+#133+' https://cli.github.com/manual'));
End;

Procedure PrintCmdLine(Const Nm:AnsiString);
Begin
 WriteLn('  ',PadR(Nm+':',13),DescOf(Nm));
End;

Procedure PrintMainHelp;
Begin
 WriteLn(Lg('Work seamlessly with GitHub from the command line.','Travaillez avec GitHub depuis la ligne de commande.'));
 WriteLn;
 WriteLn(Lg('USAGE','UTILISATION'));
 WriteLn('  gh <',Lg('command','commande'),'> <',Lg('subcommand','sous-commande'),'> [flags]');
 WriteLn;
 WriteLn(Lg('CORE COMMANDS','COMMANDES PRINCIPALES'));
 PrintCmdLine('auth');PrintCmdLine('browse');PrintCmdLine('codespace');PrintCmdLine('gist');
 PrintCmdLine('issue');PrintCmdLine('org');PrintCmdLine('pr');PrintCmdLine('project');
 PrintCmdLine('release');PrintCmdLine('repo');
 WriteLn;
 WriteLn(Lg('GITHUB ACTIONS COMMANDS','COMMANDES GITHUB ACTIONS'));
 PrintCmdLine('cache');PrintCmdLine('run');PrintCmdLine('workflow');
 WriteLn;
 WriteLn(Lg('ALIAS COMMANDS','COMMANDES D''ALIAS'));
 WriteLn('  ',PadR('co:',13),Lg('Alias for "pr checkout"','Alias de "pr checkout"'));
 WriteLn;
 WriteLn(Lg('ADDITIONAL COMMANDS','COMMANDES SUPPL'+#144+'MENTAIRES'));
 PrintCmdLine('alias');PrintCmdLine('api');PrintCmdLine('completion');PrintCmdLine('config');
 PrintCmdLine('extension');PrintCmdLine('gpg-key');PrintCmdLine('label');PrintCmdLine('ruleset');
 PrintCmdLine('search');PrintCmdLine('secret');PrintCmdLine('ssh-key');PrintCmdLine('status');
 PrintCmdLine('variable');
 WriteLn;
 WriteLn(Lg('HELP TOPICS','SUJETS D''AIDE'));
 WriteLn('  ',PadR('environment:',13),Lg('Environment variables that can be used with gh','Variables d''environnement utilisables avec gh'));
 WriteLn('  ',PadR('exit-codes:',13),Lg('Exit codes used by gh','Codes de sortie utilis'+#130+'s par gh'));
 WriteLn('  ',PadR('formatting:',13),Lg('Formatting options for JSON data exported from gh','Options de formatage des donn'+#130+'es JSON export'+#130+'es par gh'));
 WriteLn('  ',PadR('reference:',13),Lg('A comprehensive reference of all gh commands','R'+#130+'f'+#130+'rence compl'+#138+'te de toutes les commandes gh'));
 WriteLn;
 WriteLn(Lg('FLAGS','OPTIONS'));
 WriteLn('  --help      ',Lg('Show help for command','Affiche l''aide de la commande'));
 WriteLn('  --version   ',Lg('Show gh version','Affiche la version de gh'));
 WriteLn;
 WriteLn(Lg('EXAMPLES','EXEMPLES'));
 WriteLn('  $ gh issue create');
 WriteLn('  $ gh repo clone cli/cli');
 WriteLn('  $ gh pr checkout 321');
 WriteLn;
 WriteLn(Lg('LEARN MORE','EN SAVOIR PLUS'));
 WriteLn('  ',Lg('Use `gh <command> <subcommand> --help` for more information about a command.',
   'Utilisez `gh <commande> <sous-commande> --help` pour plus d''informations sur une commande.'));
 WriteLn('  ',Lg('Read the manual at https://cli.github.com/manual','Lisez le manuel '+#133+' https://cli.github.com/manual'));
End;

Procedure PrintTopic(Const T:AnsiString);
Var
 I:LongInt;
 Cmds:TSList;
 Subs:TSList;
 J:LongInt;
Begin
 If T='environment' Then Begin
  WriteLn('GH_TOKEN, GITHUB_TOKEN (in order of precedence): an authentication token that will be used when a command targets either github.com or a subdomain of ghe.com.');
  WriteLn;
  WriteLn('GH_ENTERPRISE_TOKEN, GITHUB_ENTERPRISE_TOKEN (in order of precedence): an authentication token for API requests to GitHub Enterprise.');
  WriteLn;
  WriteLn('GH_HOST: specify the GitHub hostname for commands where a hostname has not been provided, or cannot be inferred from the context of a local Git repository.');
  WriteLn;
  WriteLn('GH_REPO: specify the GitHub repository in the "[HOST/]OWNER/REPO" format for commands that otherwise operate on a local repository.');
  WriteLn;
  WriteLn('GH_EDITOR, GIT_EDITOR, VISUAL, EDITOR (in order of precedence): the editor tool to use for authoring text.');
  WriteLn;
  WriteLn('GH_BROWSER, BROWSER (in order of precedence): the web browser to use for opening links.');
  WriteLn;
  WriteLn('GH_CONFIG_DIR: the directory where gh will store configuration files.');
  WriteLn;
  WriteLn('GH_PROMPT_DISABLED: set to any value to disable interactive prompting in the terminal.');
  WriteLn;
  WriteLn('GH_FORCE_TTY: set to any value to force terminal-style output even when the output is redirected.');
  WriteLn;
  WriteLn('LANGUAGE: set to EN to display the help in English (French by default).');
 End
 Else If T='exit-codes' Then Begin
  WriteLn('gh follows normal conventions regarding exit codes.');
  WriteLn;
  WriteLn('- If a command completes successfully, the exit code will be 0');
  WriteLn;
  WriteLn('- If a command fails for any reason, the exit code will be 1');
  WriteLn;
  WriteLn('- If a command is running but gets cancelled, the exit code will be 2');
  WriteLn;
  WriteLn('- If a command encounters an authentication issue, the exit code will be 4');
  WriteLn;
  WriteLn('NOTE: It is possible that a particular command may have more exit codes, so it is a good');
  WriteLn('practice to check documentation for the command if you are relying on exit codes to');
  WriteLn('control some behavior.');
 End
 Else If T='formatting' Then Begin
  WriteLn('By default, the result of `gh` commands are output in line-based plain text format.');
  WriteLn('Some commands support passing the `--json` flag, which converts the output to JSON format.');
  WriteLn('Once in JSON, the output can be further formatted according to a required formatting string by');
  WriteLn('adding either the `--jq` or `--template` flag. This is convenient for making the output of');
  WriteLn('specific commands accessible to automation scripts or for other use cases.');
  WriteLn;
  WriteLn('For more information about jq, see https://jqlang.github.io/jq/manual/.');
  WriteLn;
  WriteLn('The `--template` flag accepts Go templates (https://golang.org/pkg/text/template/) with these');
  WriteLn('additional functions: autocolor, color, join, pluck, tablerender, tablerow, timeago, timefmt,');
  WriteLn('truncate, hyperlink.');
  WriteLn;
  WriteLn('Examples:');
  WriteLn('  $ gh issue list --json number,title --jq ''.[] | "\(.number)\t\(.title)"''');
  WriteLn('  $ gh pr list --json number,title --template ''{{range .}}{{tablerow .number .title}}{{end}}{{tablerender}}''');
 End
 Else If T='reference' Then Begin
  WriteLn('# gh reference');
  ListSubs('',Cmds);
  SSort(Cmds);
  For I:=0 to Cmds.N-1 do Begin
   WriteLn;
   WriteLn('## `gh ',Cmds.A[I],'`');
   WriteLn;
   ListSubs(Cmds.A[I],Subs);
   If Subs.N=0 Then Begin
    RunShell(Q(ParamStr(0))+' '+Cmds.A[I]+' --help');
   End
   Else Begin
    SSort(Subs);
    For J:=0 to Subs.N-1 do Begin
     WriteLn('### `gh ',Cmds.A[I],' ',Subs.A[J],'`');
     WriteLn;
     RunShell(Q(ParamStr(0))+' '+Cmds.A[I]+' '+Subs.A[J]+' --help');
     WriteLn;
    End;
   End;
  End;
 End
 Else Begin
  Die2('unknown help topic "'+T+'"',1);
 End;
End;

Procedure CmdHelp;
Var
 I:LongInt;
 Cmd:AnsiString;
Begin
 If(ArgStart>ParamCount)Then Begin PrintMainHelp;Halt(0);End;
 Cmd:=ParamStr(ArgStart);
 If(Cmd='environment')or(Cmd='exit-codes')or(Cmd='formatting')or(Cmd='reference')or(Cmd='mintty')or
   (Cmd='accessibility')or(Cmd='actions')Then Begin
  If(Cmd='mintty')or(Cmd='accessibility')or(Cmd='actions')Then Begin
   WriteLn(Lg('See https://cli.github.com/manual for details on this topic.',
     'Consultez https://cli.github.com/manual pour plus de d'+#130+'tails sur ce sujet.'));
   Halt(0);
  End;
  PrintTopic(Cmd);Halt(0);
 End;
 Cmd:='';
 For I:=ArgStart to ParamCount do Cmd:=Cmd+' '+Q(ParamStr(I));
 Halt(RunShell(Q(ParamStr(0))+Cmd+' --help'));
End;
Const
 NDsp=46;
 Disp:Array[0..NDsp-1]of TDisp=(  (P:'alias delete';F:@CmdAliasDelete),
  (P:'alias imports';F:@CmdAliasImports),
  (P:'alias list';F:@CmdAliasList),
  (P:'alias set';F:@CmdAliasSet),
  (P:'api';F:@CmdApi),
  (P:'auth git-credential';F:@CmdAuthGitCred),
  (P:'auth login';F:@CmdAuthLogin),
  (P:'auth logout';F:@CmdAuthLogout),
  (P:'auth refresh';F:@CmdAuthRefresh),
  (P:'auth setup-git';F:@CmdAuthSetupGit),
  (P:'auth status';F:@CmdAuthStatus),
  (P:'auth switch';F:@CmdAuthSwitch),
  (P:'auth token';F:@CmdAuthToken),
  (P:'browse';F:@CmdBrowse),
  (P:'completion';F:@CmdCompletion),
  (P:'config clear-cache';F:@CmdConfigClear),
  (P:'config get';F:@CmdConfigGet),
  (P:'config list';F:@CmdConfigList),
  (P:'config set';F:@CmdConfigSet),
  (P:'help';F:@CmdHelp),
  (P:'org list';F:@CmdOrgList),
  (P:'repo archive';F:@CmdRepoArchive),
  (P:'repo autolink create';F:@CmdAutolinkCreate),
  (P:'repo autolink delete';F:@CmdAutolinkDelete),
  (P:'repo autolink list';F:@CmdAutolinkList),
  (P:'repo autolink view';F:@CmdAutolinkView),
  (P:'repo clone';F:@CmdRepoClone),
  (P:'repo create';F:@CmdRepoCreate),
  (P:'repo delete';F:@CmdRepoDelete),
  (P:'repo deploy-key add';F:@CmdDeployKeyAdd),
  (P:'repo deploy-key delete';F:@CmdDeployKeyDelete),
  (P:'repo deploy-key list';F:@CmdDeployKeyList),
  (P:'repo edit';F:@CmdRepoEdit),
  (P:'repo fork';F:@CmdRepoFork),
  (P:'repo gitignore list';F:@CmdGitignoreList),
  (P:'repo gitignore view';F:@CmdGitignoreView),
  (P:'repo license list';F:@CmdLicenseList),
  (P:'repo license view';F:@CmdLicenseView),
  (P:'repo list';F:@CmdRepoList),
  (P:'repo rename';F:@CmdRepoRename),
  (P:'repo set-default';F:@CmdRepoSetDefault),
  (P:'repo sync';F:@CmdRepoSync),
  (P:'repo unarchive';F:@CmdRepoUnarchive),
  (P:'repo view';F:@CmdRepoView),
  (P:'status';F:@CmdStatus),
  (P:'version';F:@CmdVersion));

Function FindDisp(Const Path:AnsiString):TProc;
Var
 I:LongInt;
Begin
 FindDisp:=Nil;
 For I:=0 to NDsp-1 do If Disp[I].P=Path Then Begin FindDisp:=Disp[I].F;Exit;End;
End;

Function SelfCmd:AnsiString;
Begin
 SelfCmd:=Q(ParamStr(0));
End;

{ remplace $1..$9 dans l'expansion d'un alias ; renvoie le reste des arguments }
Function ExpandAliasText(Const Ex:AnsiString;First:LongInt;Quote:Boolean):AnsiString;
Var
 R:AnsiString;
 I,Used:LongInt;
 A:AnsiString;
Begin
 R:=Ex;Used:=0;
 For I:=1 to 9 do Begin
  If Pos('$'+IStr(I),R)>0 Then Begin
   If First+I-1<=ParamCount Then A:=ParamStr(First+I-1) Else A:='';
   If Quote Then A:=Q(A);
   R:=ReplaceAll(R,'$'+IStr(I),A);
   If I>Used Then Used:=I;
  End;
 End;
 For I:=First+Used to ParamCount do Begin
  If Quote Then R:=R+' '+Q(ParamStr(I)) Else R:=R+' '+ParamStr(I);
 End;
 ExpandAliasText:=R;
End;

Procedure RunAlias(Const Nm:AnsiString);
Var
 Ex:AnsiString;
Begin
 Ex:=YGet(CfgY,'aliases|'+Nm);
 If(Ex<>'')and(Ex[1]='!')Then Begin
  Ex:=ExpandAliasText(Copy(Ex,2,Length(Ex)),2,True);
  Halt(RunShell(Ex));
 End;
 Ex:=ExpandAliasText(Ex,2,True);
 Halt(RunShell(SelfCmd+' '+Ex));
End;

{ extension installee : gh-NOM dans le repertoire des extensions }
Function ExtensionPath(Const Nm:AnsiString):AnsiString;
Var
 D,P:AnsiString;
Begin
 D:=JoinPath(JoinPath(DataDir,'extensions'),'gh-'+Nm);
 P:=JoinPath(D,'gh-'+Nm);
 {$IFDEF WINDOWS}
 If FileExists_(P+'.exe')Then Begin ExtensionPath:=P+'.exe';Exit;End;
 {$ENDIF}
 If FileExists_(P)Then ExtensionPath:=P Else ExtensionPath:='';
End;

Procedure NoSuchCommand(Const Parent,Sub:AnsiString);
Begin
 WriteLn(StdErr,'unknown command "',Sub,'" for "',Parent,'"');
 WriteLn(StdErr);
 WriteLn(StdErr,Lg('Run ''','Ex'+#130+'cutez '''),IfThen_(Parent='gh','gh',Parent),Lg(' --help'' for usage.',' --help'' pour l''aide.'));
 Halt(1);
End;

Procedure Run;
Var
 C,W2,W3,Path:AnsiString;
 P:TProc;
 N,I:LongInt;
 Ext,Cmd:AnsiString;
Begin
 If ParamCount=0 Then Begin PrintMainHelp;Halt(0);End;
 C:=ParamStr(1);
 If(C='-h')or(C='--help')or(C='/?')Then Begin PrintMainHelp;Halt(0);End;
 If(C='--version')or(C='-v')Then Begin
  WriteLn('gh version ',ToolVersion,' (pascal)');
  WriteLn('https://github.com/cli/cli/releases/latest');
  Halt(0);
 End;
 If C='co' Then Begin
  Cmd:='';
  For I:=2 to ParamCount do Cmd:=Cmd+' '+Q(ParamStr(I));
  Halt(RunShell(SelfCmd+' pr checkout'+Cmd));
 End;
 If(not IsBuiltinCmd(C))and YHas(CfgY,'aliases|'+C)Then RunAlias(C);
 If ParamCount>=2 Then W2:=ParamStr(2) Else W2:='';
 If ParamCount>=3 Then W3:=ParamStr(3) Else W3:='';
 { plus longue correspondance : trois mots, deux mots, un mot }
 N:=0;P:=Nil;
 If(W3<>'')and(W2<>'')and(Copy(W2,1,1)<>'-')and(Copy(W3,1,1)<>'-')Then Begin
  P:=FindDisp(C+' '+W2+' '+W3);
  If Assigned(P)Then N:=3;
 End;
 If(N=0)and(W2<>'')and(Copy(W2,1,1)<>'-')Then Begin
  P:=FindDisp(C+' '+W2);
  If Assigned(P)Then N:=2;
 End;
 If N=0 Then Begin
  P:=FindDisp(C);
  If Assigned(P)Then N:=1;
 End;
 If N>0 Then Begin
  ArgStart:=N+1;
  P();
  Exit;
 End;
 { groupes de commandes }
 If DescOf(C)<>'' Then Begin
  If(W2='')or(W2='-h')or(W2='--help')or(W2='/?')Then Begin PrintGroupHelp(C);Halt(0);End;
  { groupe imbrique (repo autolink) }
  If(DescOf(C+' '+W2)<>'')and((W3='')or(W3='-h')or(W3='--help'))Then Begin
   PrintGroupHelp(C+' '+W2);Halt(0);
  End;
  If Copy(W2,1,1)<>'-' Then NoSuchCommand('gh '+C,W2);
  PrintGroupHelp(C);Halt(0);
 End;
 { extensions }
 Ext:=ExtensionPath(C);
 If Ext<>'' Then Begin
  Cmd:='';
  For I:=2 to ParamCount do Cmd:=Cmd+' '+Q(ParamStr(I));
  Halt(RunShell(Q(Ext)+Cmd));
 End;
 NoSuchCommand('gh',C);
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
 LoadConfig;
 ApiHost:=DefaultHost;
 Run;
End.

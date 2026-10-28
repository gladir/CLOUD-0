# CLOUD-0
Suite de commande écrit en Turbo Pascal/Free Pascal pour l'infonuagique (Cloud).

<h2>Liste des fichiers</h2>

Voici la liste des différents fichiers proposés dans CLOUD-0 :

<table>
  <tr>
    <th>Commande</th>
    <th>Description</th>
   </tr>
</tr>
  <tr>
     <td><b>HF.PAS</b></td>
     <td>Cette commande permet de gérer le Hugging Face Hub à la manière de la commande <code>hf</code> : authentification (<code>auth login|logout|whoami|list|switch</code>), téléchargement de modèles, jeux de données et Spaces avec cache et reprise (<code>download</code>), envoi de fichiers et dossiers avec LFS (<code>upload</code>), consultation (<code>models|datasets|spaces ls|info</code>), gestion des dépôts, du cache local, des collections, des discussions, des Jobs et des Inference Endpoints. Ce n'est pas un moteur d'exécution de modèles.</td>
  </tr>
</table>


<h2>Compilation</h2>
	
Les fichiers Pascal n'ont aucune dépendances, il suffit de télécharger le fichier désiré et de le compiler avec Free Pascal avec la syntaxe de commande  :

<pre><b>fpc</b> <i>LEFICHIER.PAS</i></pre>
	
Sinon, vous pouvez également le compiler avec le Turbo Pascal à l'aide de la syntaxe de commande suivante :	

<pre><b>tpc</b> <i>LEFICHIER.PAS</i></pre>
	
<h2>Licence</h2>
<ul>
 <li>Le code source est publié sous la licence <a href="https://github.com/gladir/CLOUD-0/blob/master/LICENSE">MIT</a>.</li>
 <li>Le paquet original est publié sous la licence <a href="https://github.com/gladir/CLOUD-0/blob/master/LICENSE">MIT</a>.</li>
</ul>

LiveRsync
=========

Real-time synchronisation with remote Rsync server (Powershell)

INSTALLATION GUIDE
==================

1. Copier le dossier LiveRsync sur la machine cliente.

2. Créer un raccourci vers launch.vbs

  Déplacer ce raccourci dans le dossier 'Démarrage' du menu Démarrer en le renommant 'LiveRsyncv2'
	
3. Configurer Powershell, exécuter en tant qu'admin:
	
  `Set-ExecutionPolicy RemoteSigned`

  `Enable-PSRemoting -Force`
	
4. Configurer LiveRsync via le fichier 'conf.xml'

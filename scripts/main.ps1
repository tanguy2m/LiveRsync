# Chargement des assemblies
[System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null # Pas de sortie sur la console
[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null # Pas de sortie sur la console

# Récupération du dossier d'installation
$installFolder = Split-Path -parent $MyInvocation.MyCommand.Definition | Split-Path -parent
# Récupération de la config depuis le fichier xml
[xml]$xml = Get-Content ($installFolder | Join-path -childpath "config.xml")

# Création de la form chapeau
$form = new-object System.Windows.Forms.form
$form.ShowInTaskbar = $false 
$form.WindowState = "minimized"
$form.Add_Shown({$form.Activate()})

# Timer permettant la réalisation d'évènements externes
$timer1 = New-Object System.Windows.Forms.Timer
$timer1.Enabled = $true
$timer1.interval = 1000
$timer1.Start()
$timer1.Add_Tick({$form.Refresh()})

# Création de la Notify icon
$ni = new-object System.Windows.Forms.NotifyIcon
$ni = $ni
$ni.Icon = New-object System.Drawing.Icon($installFolder | Join-path -childpath "explorer.ico") 
$ni.ContextMenu = new-object System.Windows.Forms.ContextMenu
$ni.Text = "LiveRsync"
#$NI.ShowBalloonTip(10,$sender.Path,"$($e.FullPath) => $($e.ChangeType)",[system.windows.forms.ToolTipIcon]"Warning") # Test only

function Log
{param([string]$dossier,[string]$info)

	$line = (Get-Date –f "yyyy-MM-dd HH:mm:ss - ") + $info
	Write-Host $line
	
	$couple = $xml.Config.Dossiers.Dossier | Where-Object { $_.Origine -match $dossier.Replace("\","\\") } #TODO: faire le calcul ailleurs
	$destination = $couple.Destination
	
	$line | Add-Content -Encoding UTF8 -path ($installFolder | Join-path -childpath "logs\$destination.txt") # Fichier en UTF-8
}

$restart = [Hashtable]::Synchronized(@{})

function global:SauvJob
{param([string]$source)

	$job = Start-Job `
		-Name $source `
		-filepath .\scripts\sauvegarde.ps1 `
		-ArgumentList $source,$installFolder
	Register-ObjectEvent `
		-SourceIdentifier "Event $source" `
		-InputObject $job `
		-EventName StateChanged `
		-Action {
			Unregister-Event $eventsubscriber.SourceIdentifier # Arrêt de l'écoute de l'évènement
			Remove-Job -Name $eventsubscriber.SourceIdentifier # Suppression du job lié à l'event
			Remove-Job -job $eventsubscriber.SourceObject # Suppression du job de sauvegarde
			$dossier = $eventsubscriber.SourceObject.Name
			if($event.MessageData[$dossier] -eq $true)
			{
				$event.MessageData[$dossier] = $false
				SauvJob $dossier
			}			
		} `
		-MessageData $restart
}

# Fonction dmdSauv: demande la création d'un job de sauvegarde en fonction de l'état du job courant
function dmdSauv($sender,$e) {
	
	#Détermination de l'origine
	if($sender.GetType().FullName -eq "System.IO.FileSystemWatcher")
	{
		$dossier = $sender.Path
		$prefix = "$($e.ChangeType): $($e.FullPath.Replace($sender.Path,''))"
	}
	elseif($sender.GetType().FullName -eq "System.Windows.Forms.MenuItem")
	{
		$dossier = $sender.Parent.MenuItems[0].Text
		$prefix = "Demande manuelle"
	}
	
	try
    {
		# Tentative de récupération du job en cours
		$sauvJob = Get-Job -EA Stop -Name $dossier #-EA Stop: lève une exception en cas d'erreur
		if($sauvJob.State -eq "Running") # Job de sauvegarde en cours
		{
			$restart[$dossier] = $true #Dans les 2 cas, le job devra redémarrer
			$progress = $sauvJob.ChildJobs[0].progress | %{$_.StatusDescription};
			if($progress -eq "Rsync")
			{
				Log $dossier "$prefix => Rsync en cours, reset demandé"
			}
			elseif($progress -eq "Buffer")
			{
				Log $dossier "$prefix => Reset du buffer de sauvegarde"
				Stop-job -job $sauvJob
			}
		}
    }
    catch # Le get-job n'a pas trouvé le job en question
    {
		Log $dossier "$prefix => Lancement d'une sauvegarde"
		SauvJob $dossier
    }	
}

# Fonction permettant d'ouvrir le fichier de log d'un dossier
function openLog($sender,$e) {
	$dossier = $Sender.Parent.MenuItems[0].Text
	
	$couple = $xml.Config.Dossiers.Dossier | Where-Object { $_.Origine -match $dossier.Replace("\","\\") }
	$destination = $couple.Destination
	
	$installFolder | Join-path -childpath "logs\$destination.txt" | Invoke-Item
}

$fsWatchers = @()
# Récupération des dossiers à monitorer et remplissage du menu contextuel 
foreach( $dossier in $xml.Config.Dossiers.Dossier){

	$origine = $dossier.Origine # Récupération du dossier origine
	$destination = $dossier.Destination 
	
	if ([system.io.directory]::exists($origine)) {
	
		# Création et configuration du FileSystemWatcher
		$fsw = new-object System.IO.FileSystemWatcher $dossier.Origine 
		$fsw.IncludeSubDirectories = $true 
		$fsw.SynchronizingObject = $form # Nécessaire ??	
		$fsw.add_Changed($function:dmdSauv)
		$fsw.add_Created($function:dmdSauv) 
		$fsw.add_Deleted($function:dmdSauv)
		$fsw.add_Renamed($function:dmdSauv)
		$fsWatchers += $fsw
		
		$restart.Add($dossier.Origine,$false)
		
		# Ajout du dossier au menu contextuel
		$items = $ni.contextMenu.MenuItems.Add($destination).MenuItems
		$items.Add((New-Object System.Windows.Forms.MenuItem -Property @{                            
			Text = $origine
			Enabled = $false
		})) | Out-null # Ajout du sous-menu désactivé donnant le chemin d'accès au dossier
		$items.Add("Lancer sauvegarde",$function:dmdSauv) | Out-null # Ajout du sous-menu permettant de déclencher une sauvegarde
		$items.Add("Ouvrir log",$function:openLog) | Out-null # Ajout du sous-menu permettant de déclencher une sauvegarde
	} 
	else {} # TODO: il faudrait logguer une erreur 
}

# Ajout du bouton QUITTER au menu contextuel
$ni.contextMenu.MenuItems.Add("Quitter",`
{ 
	foreach( $fs in $fsWatchers){ # Ménage des FileSystem watchers
		$fs.EnableRaisingEvents = $false;
	}
	$NI.Visible = $False
	$form.close()
}) | Out-null

#Fire it up
foreach( $fs in $fsWatchers){
	$fs.EnableRaisingEvents = $true;
}
$NI.Visible = $True;
$form.showdialog() 
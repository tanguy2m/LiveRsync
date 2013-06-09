Param ([string]$origine,[string]$installFolder)

[xml]$xml = Get-Content ($installFolder | Join-path -childpath "config.xml")
$destination = ($xml.Config.Dossiers.Dossier | Where-Object { $_.Origine -match $origine.Replace("\","\\") }).Destination

function Log
{param([string]$info)
	$line = (Get-Date –f "yyyy-MM-dd HH:mm:ss - ") + "SAUVEGARDE: $info"
	Write-Host $line
	$line | Add-Content -Encoding UTF8 -path ($installFolder | Join-path -childpath "logs\$destination.txt") # Fichier en UTF-8
}

###########################################################
# Fonction vérifiant l'accessibilité du NAS
###########################################################
$ipNAS = "";
Function NASaccessible()
{
    try
    {
        # Récupération de l'adresse IP du serveur appelé NAS
        $script:ipNAS = [System.Net.Dns]::GetHostByName($xml.Config.Server.Name).AddressList[0].IpAddressToString
        # Ping du NAS
        $pingNAS = (new-object System.Net.NetworkInformation.Ping).Send($ipNAS)
        
        if($pingNAS) # Si la machine NAS répond
        {
            $arpTable = arp -a; # Récupération de la table ARP
            ($arpTable | ? {$_ -match $ipNAS}) -match "([0-9A-F]{2}([:-][0-9A-F]{2}){5})" | out-null;
			if ($matches[0] -eq $xml.Config.Server.MAC)
			{
				Log "'$($xml.Config.Server.Name)' accessible à l'adresse $ipNAS"
				Return $true;
			}
			else
			{
				Log "La machine '$($xml.Config.Server.Name)' de ce réseau n'est pas la notre."
				Return $false;
			}
        }
        else
        {
			Log "'$($xml.Config.Server.Name)' connu mais inaccessible."
            return $false # La machine NAS n'est pas accessible
        }
    }
    catch [System.Net.Sockets.SocketException] # La machine NAS est inconnue
    {
		Log "'$($xml.Config.Server.Name)' inconnu sur le réseau.`n"
        return $false
    }
}

###########################################################
# Fonction transformant un chemin windows en chemin cygwin
###########################################################
Function cygwinFormat
{Param ([string]$path)

    # Remplacement des anti-slashs
    # Suppression du ':' du lecteur
    $pathCyg = $path.Replace("\","/").Replace(":","")
    "/cygdrive/" + $pathCyg.Replace($pathCyg.Substring(0,1),$pathCyg.Substring(0,1).ToLower())
      
}

# PARAMETRES RSYNC
# ----------------
# r=récursif
# l=préserve les raccourcis
# t=préserve les timestamps
# --delete: efface de l'archive les fichiers qui ne sont plus dans le dossier source
# v= augmente le niveau de détail des opérations affichées
# --progress: affiche la progression de l'opération ## Pas pertinent dans un fichier de log donc supprimé
# --chmod=ugo=rwX: donnes les droits par défaut à destination
#      Pour le changer un peu plus: --chmod=a+rwx,g+rwx,o-wx

###################
#       MAIN
###################
Log "Début du buffer"

# Buffer pour éviter les bagotements de fichiers temporaires
Write-Progress Activity "Buffer"
Start-Sleep -Milliseconds 60000 # 1min

if(NASaccessible) # si le NAS est accessible
{
	Write-Progress Activity "Rsync"

    $cwRsyncPath = $installFolder | Join-path -childpath "cwRsync\"
    $rsyncCommand = "rsync.exe -rlt --delete -v --chmod=ugo=rwX"
    $cygOrigine = cygwinFormat "$origine\" #Origine ne doit pas contenir de '\' à la fin
	$rsyncModule = "$ipNAS::$($xml.Config.Server.RsyncModule)/"
    
    $result = Invoke-Expression "$cwRsyncPath$rsyncCommand `"$cygOrigine`" $rsyncModule$destination 2>&1" 
    $result | foreach-object {
		$line = $_.ToString()
		if($line -ne "") { Log "RSYNC: $line" } # Suppression des lignes vides dans le résultat
	}
}

Log "Fin"
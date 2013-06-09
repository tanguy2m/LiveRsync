################################################################################
# Script Powershell permettant le rsync d'un dossier si le NAS est accessible
################################################################################
# Arguments(0) = nom du fichier / dossier modifié
# Arguments(1) = type d'opération effectuée

###########################################################
# Liste des différents folders configuré pour la sauvegarde
#       Ne pas oublier le dernier anti-slash dans le chemin
###########################################################
$folders = @{}
$folders.Add("Archimaud","D:\Archimaud\")

$installFolder = Split-Path -parent $MyInvocation.MyCommand.Definition | Split-Path -parent
$ipNAS = "";

$log = (Get-Date –f "yyyy-MM-dd HH:mm:ss - ")
$log += "Fichier/Dossier: " + $args[0] + " a été " + $args[1] + "`n"

###########################################################
# Fonction vérifiant l'accessibilité du NAS
###########################################################
Function NASaccessible()
{
    try
    {
        # Récupération de l'adresse IP du serveur appelé NAS
        $script:ipNAS = [System.Net.Dns]::GetHostByName("NAS").AddressList[0].IpAddressToString
        # Ping du NAS
        $pingNAS = (new-object System.Net.NetworkInformation.Ping).Send($script:ipNAS)
        
        if($pingNAS) # Si la machine NAS répond
        {
            $arpTable = arp -a; # Récupération de la table ARP
            ($arpTable | ? {$_ -match $script:ipNAS}) -match "([0-9A-F]{2}([:-][0-9A-F]{2}){5})" | out-null;
			if ($matches[0] -eq "a0-21-b7-c0-e5-60")
			{
				Return $true;
			}
			else
			{
				$script:log += "La machine 'NAS' de ce réseau n'est pas le notre."
				Return $false;
			}
        }
        else
        {
			$script:log += "'NAS' connu mais inaccessible.`n"
            return $false # La machine NAS n'est pas accessible
        }
    }
    catch [System.Net.Sockets.SocketException] # La machine NAS est inconnue
    {
		$script:log += "'NAS' inconnu sur le réseau.`n"
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

###########################################################
# Fonction effectuant le rsync
###########################################################
#
# PARAMETRES RSYNC
# ----------------
# r=récursif
# l=préserve les raccourcis
# t=préserve les timestamps
# --delete: efface de l'archive les fichiers qui ne sont plus dans le dossier source
# v= augmente le niveau de détail des opérations affichées
# --progress: affiche la progression de l'opération
# --chmod=ugo=rwX: donnes les droits par défaut à destination
#      Pour le changer un peu plus: --chmod=a+rwx,g+rwx,o-wx

Function Sync
{Param ([string]$origine,[string]$destination)

    $cwRsyncPath = $script:installFolder | Join-path -childpath "cwRsync\"
    $rsyncCommand = "rsync.exe -rlt --delete -v --progress --chmod=ugo=rwX"
    $rsyncModule = $script:ipNAS + "::backup/"
    
    $result = Invoke-Expression "$cwRsyncPath$rsyncCommand $origine $rsyncModule$destination 2>&1"
	#$script:log += "$cwRsyncPath$rsyncCommand $origine $rsyncModule$destination`n"
    $script:log += $result | foreach-object {$_.ToString()+"`n"}
}

###################
#       MAIN
###################

# Récupération des informations du dossier
$dossierConfigure = $false
foreach($destination in $folders.keys)
{
    if($args[0].Contains($folders[$destination]))
    {        
        $origine = cygwinFormat $folders[$destination]
        $dossierConfigure = $true
        break
    }
}

if($dossierConfigure -eq $false)
{
	$log += "Dossier d'origine non configuré pour la sauvegarde`n"
}
elseif(NASaccessible) # Synchronisation du dossier s'il est configuré et si le NAS est accessible
{
    Sync $origine $destination # Lancement de la synchro
}

$log | Add-Content -path ($installFolder | Join-path -childpath "logs\log.txt")
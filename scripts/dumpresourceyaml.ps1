


# usage for dump AKS resource in yaml and create Kustomization.yaml

# required paramaters:
# $clustername: aks cluster name
# $ResourceGroupName: aks cluster resource group name 

# optional parameters:
# $excludens: namespace which will not be scanned
# $excluderesources: resource name which will be skipped during scan
# $targetresources: resource types for scan
# $rootpath: root path to dump the resource yaml
# $option: 0 (default) = reconcile kucstomization resources; 1 = dump resource yaml


# sample script command:
# ./dumpresourceyaml.ps1 -ResourceGroupName $ResourceGroupName -clustername $clustername -rootpath C:\simon\azure\aks\devops -option 1

param
(
    [parameter(Mandatory = $true)] [String] $clustername,
    [parameter(Mandatory = $true)] [String] $ResourceGroupName,
    [parameter(Mandatory = $false)] [String] $rootpath=".\",
    [parameter(Mandatory = $false)] [array] $excludens = @("gatekeeper-system","kube-node-lease","kube-system","kube-public","flux-system"),
    [parameter(Mandatory = $false)] [array] $excluderesources = @("kubernetes","kube-root-ca","default-token"),
    [parameter(Mandatory = $false)] [String] $targetresources="configmap,daemonset,deployment,service,hpa", 
    [parameter(Mandatory = $false)] [array] $removeversiontag = @("creationTimestamp","resourceVersion","selfLink", "uid"),
    [parameter(Mandatory = $false)][ValidateSet(0,1)] [int] $option = 0
)

# get ask credential
function getakscredentials  {
    [parameter(Mandatory = $true)] [String] $clustername,
    [parameter(Mandatory = $true)] [String] $ResourceGroupName

    Import-AzAksCredential -ResourceGroupName $ResourceGroupName -Name $clustername -force
}

# prepare aks cli
# Install-AzAksKubectl -Force
# prepare flux
# Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
# choco install flux
# prepare yaml powershell 
# Register-PackageSource -Name Nuget.Org -Provider NuGet -Location "https://www.nuget.org/api/v2" -erroraction ignore
# Install-Package YamlDotNet -force
# load aks credentail 
getakscredentials -ResourceGroupName $ResourceGroupName -clusternameame $clustername

# default option is to update kustomization resources. Or use option 1 to dump resource template from existing aks cluster 
if ($option -eq 0) {
    $kustomizations = $(kubectl get kustomization -n flux-system -o jsonpath='{.items[*].metadata.name}').split(" ")
    foreach($kustomizations in $kustomizations) {
        flux reconcile kustomization $kustomizations
    }

} else {
$exportpath = "$rootpath\$clustername"
$namespaces = $(kubectl get namespace -o jsonpath='{.items[*].metadata.name}').split(" ") | where {$_ -notin $excludens}
foreach ($ns in $namespaces) {

# define the Kustomization template 
$kustomization = @"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
"@

    # skip for system resource
    $resources = $(kubectl get -n $ns -o json $targetresources -o jsonpath='{.items[*].metadata.name}').split(" ") | foreach-object {
            $HasBeenMatchedYet = $false
            ForEach ($excluderesource in $excluderesources) {
                if ($_ -match $excluderesource) {
                    $HasBeenMatchedYet = $true
                    break
                }
            }   

            if ($HasBeenMatchedYet -eq $false) {
                $_
            } 
        } | Select-Object -unique
        
    if (!(test-path -path "$exportpath\$ns")) {
            mkdir "$exportpath\$ns"
        }

    foreach ($resource in $resources) {

        # try to dump resource yaml file
        write-host "export resoruce yaml: $exportpath\$ns\$resource.yaml"
        $rawtemplate = kubectl -n $ns get -o yaml $targetresources $resource --ignore-not-found=true | ConvertFrom-Yaml

        # steps to remove all version tags
        $rawtemplate.metadata.selflink = ""
    
        foreach ($item in  $rawtemplate.items) {
            # remove status
            $item.remove('status')
            foreach ($key in $removeversiontag) {
                 $item.metadata.remove($key)
            }
        }
   
        $rawtemplate | ConvertTo-Yaml | out-file -filepath "$exportpath\$ns\$resource.yaml" -force
        $kustomization+="`n- $resource.yaml"
        
    }
    # dump resource kustomization yaml
    $kustomization | out-file -filepath "$exportpath\$ns\kustomization.yaml" -force

}

}

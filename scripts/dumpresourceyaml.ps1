


# usage for dump AKS resource in yaml and create Kustomization.yaml

# required paramaters:
# $clustername: aks cluster name
# $ResourceGroupName: aks cluster resource group name 

# optional parameters:
# $excludens: namespace which will not be scanned
# $excluderesources: resource name which will be skipped during scan
# $targetresources: resource types for scan
# $rootpath: root path to dump the resource yaml
# $GitRepository: target git repository for base template
# $GitBranch: target git repository branch; default is main
# $option: 0 (default) = reconcile kucstomization resources; 1 = dump resource yaml


# sample script command:
# ./scripts/dumpresourceyaml.ps1 -ResourceGroupName $ResourceGroupName -clustername $clustername -GitRepository "https://github.com/simonxin/gitops_test" -rootpath C:\simon\azure\aks\devops -option 2

param
(
    [parameter(Mandatory = $true)] [String] $clustername,
    [parameter(Mandatory = $true)] [String] $ResourceGroupName,
    [parameter(Mandatory = $false)] [String] $rootpath=".\clusters",
    [parameter(Mandatory = $false)] [array] $excludens = @("gatekeeper-system","kube-node-lease","kube-system","kube-public","flux-system"),
    [parameter(Mandatory = $false)] [array] $excluderesources = @("kubernetes","kube-root-ca","default-token"),
    [parameter(Mandatory = $false)] [String] $targetresources="configmap,daemonset,deployment,service,hpa", 
    [parameter(Mandatory = $false)] [array] $removeversiontag = @("creationTimestamp","resourceVersion","selfLink", "uid"),
    [parameter(Mandatory = $false)] [String] $GitRepository = "https://github.com/simonxin/gitops_test",
    [parameter(Mandatory = $false)] [String] $GitBranch = "main",
    [parameter(Mandatory = $false)][ValidateSet(0,1,2)] [int] $option = 0

)

# get ask credential
function getakscredentials  {
    param (
        [parameter(Mandatory = $true)] [String] $clustername,
        [parameter(Mandatory = $true)] [String] $ResourceGroupName
    )

    Import-AzAksCredential -ResourceGroupName $ResourceGroupName -Name $clustername -force
}

# prepare aks cli
# please set tls12 if module download is failed using command: 
# [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 
# Install-AzAksKubectl -Force
# prepare flux
# Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
# choco install flux
# prepare yaml powershell
# Install-Module powershell-yaml
# if powershell-yaml cannot work, try install yamldotnet with steps below: 
# Register-PackageSource -Name Nuget.Org -Provider NuGet -Location "https://www.nuget.org/api/v2" -erroraction ignore
# Install-Package YamlDotNet -force
# load aks credentail 
getakscredentials -ResourceGroupName $ResourceGroupName -clustername $clustername

# default option is to update kustomization resources. Or use option 1 to dump resource template from existing aks cluster 
if ($option -eq 0) {
    $kustomizations = $(kubectl get kustomization -n flux-system -o jsonpath='{.items[*].metadata.name}').split(" ")
    foreach($kustomization in $kustomizations) {
        flux resume kustomization $kustomization
    }

} elseif ($option -eq 1) {

    # post-deployment suspend kustomization 
    $kustomizations = $(kubectl get kustomization -n flux-system -o jsonpath='{.items[*].metadata.name}').split(" ")
    foreach($kustomization in $kustomizations) {
        flux suspend kustomization $kustomization
    }

} elseif($option -eq 2) {
    $exportpath = "$rootpath\$clustername"
    $namespaces = $(kubectl get namespace -o jsonpath='{.items[*].metadata.name}').split(" ") | where {$_ -notin $excludens}
    foreach ($ns in $namespaces) {
    
    # define the Kustomization template 
$kustomizationtemplate = @"
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
            $kustomizationtemplate+="`n- $resource.yaml"
            
        }
        # dump resource kustomization yaml
        $kustomizationtemplate | out-file -filepath "$exportpath\$ns\kustomization.yaml" -force

        # generate git source file
        flux create source git $ns --url=$GitRepository  --branch=$GitBranch --interval=60s --export > "./clusters/$clustername/$ns-source.yaml"
        
        # generate git kustomization file
        flux create kustomization $ns --target-namespace=$ns --source=$ns --path="./$clustername/$ns" --prune=true  --interval=5m --export > "./clusters/$clustername/$ns-kustomization.yaml" 

        # add suspend = true for the kustomization file to avoid auto-update 
        $gitkscontent = get-content "./clusters/$clustername/$ns-kustomization.yaml" | ConvertFrom-Yaml
        $gitkscontent.spec.add("suspend","True")
        $gitkscontent | Convertto-Yaml | out-file -filepath "./clusters/$clustername/$ns-kustomization.yaml" -force

    }

}

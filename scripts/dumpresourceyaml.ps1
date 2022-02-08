


# usage for dump AKS resource in yaml and create Kustomization.yaml

# required paramaters:
# $clustername: aks cluster name
# $ResourceGroupName: aks cluster resource group name 

# optional parameters:
# $excludens: namespace which will not be scanned
# $excluderesources: resource name which will be skipped during scan
# $targetresources: resource types for scan
# $rootpath: root path to dump the resource yaml

# sample script command:
# dumpresourceyaml.ps1 -ResourceGroupName $ResourceGroupName -clustername $clustername -rootpath C:\simon\azure\aks\devops

param
(
    [parameter(Mandatory = $true)] [String] $clustername,
    [parameter(Mandatory = $true)] [String] $ResourceGroupName,
    [parameter(Mandatory = $false)] [String] $rootpath=".\",
    [parameter(Mandatory = $false)] [array] $excludens = @("gatekeeper-system","kube-node-lease","kube-system","kube-public","flux-system"),
    [parameter(Mandatory = $false)] [array] $excluderesources = @("kubernetes","kube-root-ca","default-token"),
    [parameter(Mandatory = $false)] [String] $targetresources="configmap,secret,daemonset,deployment,service,hpa"
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
# choco install flux



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

    foreach ($resource in $resources) {
        if (!(test-path -path "$exportpath\$ns")) {
            mkdir "$exportpath\$ns"
        }
        # try to dump resource yaml file
        write-host "export resoruce yaml: $exportpath\$ns\$resource.yaml"
        kubectl -n $ns get -o yaml $targetresources $resource --ignore-not-found=true | out-file -filepath "$exportpath\$ns\$resource.yaml" -force
        $kustomization+="`n- $resource.yaml"
        
    }
    # dump resource kustomization yaml
    $kustomization | out-file -filepath "$exportpath\$ns\kustomization.yaml" -force

}



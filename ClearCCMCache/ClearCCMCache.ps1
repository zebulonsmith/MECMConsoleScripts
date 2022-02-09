<#
Clears the config manager client cache
#>


Try {
    $ccm = New-Object -com UIResource.UIResourceMGR
} Catch {
    Throw $_
}

Try {
    $ccmcache = $ccm.getcacheinfo()
} Catch {
    Throw $_
}

$ccmcache.GetCacheElements() | ForEach-Object {$ccmcache.DeleteCacheElement($_.CacheElementId)}
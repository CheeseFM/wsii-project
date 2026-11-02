# Dot-source this file in every script:
#   . "$PSScriptRoot\..\common\config.ps1"
#   $cfg  = Get-LabConfig
#   $node = $cfg.Nodes.server1

function Get-LabConfig {
    Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot '..\config.psd1')
}

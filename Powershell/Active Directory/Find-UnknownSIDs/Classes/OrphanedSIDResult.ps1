#Requires -Version 5.1

class OrphanedSIDResult {
    [string]$ObjectDN
    [string]$ObjectClass
    [string]$OrphanedSID
    [string]$LikelySource
    [string]$Confidence
    [string]$AnalysisNotes
    [System.Security.AccessControl.AccessControlType]$AccessControlType
    [System.DirectoryServices.ActiveDirectoryRights]$ActiveDirectoryRights
    [System.Security.AccessControl.InheritanceFlags]$InheritanceType
    [System.Guid]$ObjectType
    [System.Guid]$InheritedObjectType
    [bool]$IsInherited
    [string]$ProcessingMethod
    [string]$ActionTaken
    [string]$CorrelationId
    [DateTime]$Timestamp

    OrphanedSIDResult() {
        $this.Timestamp = Get-Date
        $this.CorrelationId = [System.Guid]::NewGuid().ToString()
    }
}

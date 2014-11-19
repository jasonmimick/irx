Include (%occInclude, Ensemble)

Class Ens.Director [ Abstract, ClassType = "", ProcedureBlock, System = 4 ]
{

Parameter DOMAIN = "Ensemble";

/// This method starts the production running.
/// pProductionName: The name of the production to be started.  If not specified, defaults to the "last" production used (if any).
ClassMethod StartProduction(pProductionName As %String = {$GET(^Ens.Configuration("csp","LastProduction"))}) As %Status
{
	Set $ZT="Trap",tSC=$$$OK,tLoggedSC=0
	Do {
		If $system.License.GetFeature(1)=0 Set tSC=$$$EnsError($$$EnsErrNoEnsembleLicense) Quit
		New $roles
		// If we aren't logged in as _Ensemble call %SYS.Ensemble::StartProduction()
		If ($username '= ##class(%SYS.Ensemble).EnsembleUsername()) {
			Set tSC = ##class(%SYS.Ensemble).StartProduction(pProductionName)
			Quit
		}
		Set:'$D(^Ens.Debug) ^Ens.Debug("TraceCat","user")=1 ; force the default value to ensure jobs have an in-memory mirror and avoid repeated checks of this real global
		Lock +$$$EnsRuntime:30
		If '$Test Set tSC=$$$EnsError($$$EnsErrCanNotAcquireRuntimeLock,30) Quit

		Set tSC=..GetProductionStatus(.tProductionName,.tState) Quit:$$$ISERR(tSC)
		If tState=$$$eProductionStateRunning {
			Set tSC=$$$EnsError($$$EnsErrProductionAlreadyRunning,tProductionName)
		} ElseIf (tState=$$$eProductionStateSuspended) {
			If pProductionName'=tProductionName Set tSC=$$$EnsError($$$EnsErrProductionSuspendedMismatch,tProductionName) Quit
		} ElseIf tState=$$$eProductionStateNetworkStopped {
			If pProductionName'=tProductionName Set tSC=$$$EnsError($$$EnsErrProductionNetworkedMismatch,tProductionName) Quit			
		} ElseIf (tState=$$$eProductionStateTroubled) {
			Set tSC=$$$EnsError($$$EnsErrProductionNotShutdownCleanly,tProductionName)
		}
		Quit:$$$ISERR(tSC)

		#; Check that a (valid) production name was given
		If '$ZNAME(pProductionName,1) || '##class(Ens.Config.Production).%ExistsId(pProductionName) {
			Set tSC=$$$EnsError($$$EnsErrInvalidProduction)
			Quit
		}

		#; Since clean up of Ens.RuntimeAppData during stop production is outside of a transaction make sure empty before start
		Kill $$$EnsRuntimeAppData
		#; Now that we think this is going to work, let's remember this as the last production and setup start/stop times
		$$$EnsMirrorIndexReset
		Set tStartTime = $$$timeUTC
		Set ^Ens.Configuration("csp","LastProduction") = pProductionName
		Set ^Ens.Configuration("csp","Activity",pProductionName,"started") = tStartTime
		Kill ^Ens.Configuration("csp","Activity",pProductionName,"stopped")

		Set tSC=..findProductionDifferences(pProductionName,0,.tDefinition,.tToStopJob,.tToStartConfig,.tToDeleteConfig,.tToUpdateScheduler,,.tActorForceDisabled)  Quit:$$$ISERR(tSC)

		$$$LOGINFO($$$FormatText($$$Text("Production '%1' starting..."),pProductionName))
		If tActorForceDisabled $$$LOGWARNING("Ens.Actor is disabled because there are disabled BusinessProcesses that use the Ens.Actor queue.")

		Set tSC=$zobjclassmethod(pProductionName,"OnStart",tStartTime)  Quit:$$$ISERR(tSC)

		#; restore the queue
		Merge $$$EnsQueue=$$$EnsSuspended($$$SystemName,"Ens.Queue")
		Kill $$$EnsSuspended($$$SystemName,"Ens.Queue")
		Set tQueueName="" For { Set tQueueName=$Order($$$EnsQueue(tQueueName))  Quit:tQueueName=""
			If tQueueName'?1.N {
				Do $system.Event.Create(##class(Ens.Queue).EventName(tQueueName))
				$$$sysTRACE($$$FormatText($$$Text("event '%1' created."),##class(Ens.Queue).EventName(tQueueName)))
			}
		}
		#; restore SuspendedAppData
		Kill $$$EnsSuspendedAppData
		Merge $$$EnsSuspendedAppData=$$$EnsSuspended($$$SystemName,"AppData")
		Kill $$$EnsSuspended($$$SystemName,"AppData")
		#; initial register done by the first system in networked environment
		If $data($$$EnsRuntime)=0 {
			Set $$$EnsRuntime("Name")=pProductionName
			Set $$$EnsRuntime("StartTime")=tStartTime
			Set tCheckSum=$r(1000000000)
			Set $$$EnsRuntime("CheckSum")=tCheckSum
		}
		Set $$$EnsRuntime("System",$$$SystemName)=$p($zu(54,13,$zu(54,0)),",",1)_":"_$get(^%SYS("SSPort"),1972)_":"_$znspace

		Set ^%SYS("Ensemble","RunningNamespace",$znspace)=$$$EnsRuntime("CheckSum")

		#; Clear existing Monitor information (except host-counters)
		$$$KillAllHostMonitor
		$$$KillAllJobMonitor
		$$$KillAllLogMonitor

		Set tSC=..actualizeProductionDifferences(.tDefinition,.tToStopJob,.tToStartConfig,.tToDeleteConfig,.tToUpdateScheduler,0,0)
		If $$$ISERR(tSC) $$$LOGSTATUS(tSC)  Set:'$D($$$EnsJobStatus($$$SystemName)) $$$EnsJobStatus($$$SystemName)=""  Do ..StopProduction(1,1)  Set tLoggedSC=1  Quit
		$$$LOGINFO($$$FormatText($$$Text("Production '%1' started."),pProductionName))
		Set tSC2 = $$$AuditStartStopProduction(pProductionName,"start") 
	} While 0
Exit
	Lock -$$$EnsRuntime
	If $$$ISERR(tSC) && 'tLoggedSC $$$LOGSTATUS(tSC)
	Quit tSC
Trap
	Set $ZT="",tSC=$$$SystemError
	Goto Exit
}

/// This method updates the running production.
/// pTimeout: How many seconds to wait for the jobs to go down.
/// pForce:   It indicates if we should forcefully kill the jobs which can not stop by themselves.
/// pCalledByScheduleHandler: This parameter is set to one when it is called by the schedule handler.
ClassMethod UpdateProduction(pTimeout As %Numeric = 10, pForce As %Boolean = 0, pCalledByScheduleHandler As %Boolean = 0) As %Status
{
	Set $ZT="Trap",tSC=$$$OK
	Do {

		If $system.License.GetFeature(1)=0 Set tSC=$$$EnsError($$$EnsErrNoEnsembleLicense) Quit
		New $roles
		// If we aren't logged in as _Ensemble call %SYS.Ensemble::UpdateProduction()
		If ($username '= ##class(%SYS.Ensemble).EnsembleUsername()) {
			Set tSC = ##class(%SYS.Ensemble).UpdateProduction(pTimeout,pForce,pCalledByScheduleHandler)
			Quit
		}

		Lock +$$$EnsRuntime:30
		If '$Test Set tSC=$$$EnsError($$$EnsErrCanNotAcquireRuntimeLock,30) Quit

		Set tSC=..GetProductionStatus(.tProductionName,.tState) Quit:$$$ISERR(tSC)
		If tState'=$$$eProductionStateRunning {
			$$$sysTRACE($$$Text("No Production is running.")) Quit
		}
		$$$LOGINFO($$$FormatText($$$Text("Production '%1' updating..."),tProductionName))

		Set tSC=..findProductionDifferences(tProductionName,1,.tDefinition,.tToStopJob,.tToStartConfig,.tToDeleteConfig,.tToUpdateScheduler)  Quit:$$$ISERR(tSC)

		If '$data(tToStopJob),'$data(tToStartConfig),'$data(tToDeleteConfig),$g(tToUpdateScheduler)=0 {
			$$$LOGINFO($$$FormatText($$$Text("Production '%1' is up-to-date."),tProductionName))
		} Else {
			Do ##class(Ens.Job).CleanUpDeadJobs()
			if pCalledByScheduleHandler set tToUpdateScheduler=0
			Set tSC=..actualizeProductionDifferences(.tDefinition,.tToStopJob,.tToStartConfig,.tToDeleteConfig,.tToUpdateScheduler,pTimeout,pForce)  Quit:$$$ISERR(tSC)
			$$$LOGINFO($$$FormatText($$$Text("Production '%1' updated."),tProductionName))
		}
	} While 0
Exit
	Lock -$$$EnsRuntime
	If $$$ISERR(tSC) $$$LOGSTATUS(tSC)
	Quit tSC
Trap
	Set $ZT="",tSC=$$$SystemError
	Goto Exit
}

/// This method stops the running production.
/// pTimeout: How many seconds to wait for the jobs to go down.
/// pForce:   It indicates if we should forcefully kill the jobs which can not stop by themselves.
ClassMethod StopProduction(pTimeout As %Numeric = 10, pForce As %Boolean = 0) As %Status
{
	Set $ZT="Trap",tSC=$$$OK
	Do {
		New $roles
		// If we aren't logged in as _Ensemble call %SYS.Ensemble::StopProduction()
		If ($username '= ##class(%SYS.Ensemble).EnsembleUsername()) {
			Set tSC = ##class(%SYS.Ensemble).StopProduction(pTimeout,pForce)
			Quit
		}

		$$$LOGINFO($$$Text("StopProduction initiated."))

		Do ##class(Ens.Job).MarkDeadJobs()

		Lock +$$$EnsRuntime:30
		If '$Test Set tSC=$$$EnsError($$$EnsErrCanNotAcquireRuntimeLock,30) Quit

		Set tConfigName="" For { Set tConfigName=$Order($$$ConfigRoot(tConfigName))  Quit:tConfigName=""  Continue:tConfigName="%Production"
			Set tConfigNamesSaved(tConfigName)=$$$ConfigClassName(tConfigName)
		}
		Set tSC=..GetProductionStatus(.tProductionName,.tState) Quit:$$$ISERR(tSC)
		If tState'=$$$eProductionStateRunning {
			$$$LOGINFO($$$Text("No Production is running (")_##class(EnsPortal.Utils).resolveProductionStateName(tState)_")")
			Quit
		}
		Set tSC=##class(Ens.Job).MakeQuiescent(pTimeout,.tIsQuiescent) If $$$ISERR(tSC) Quit
		If 'tIsQuiescent,pForce=0 {
			Set tSC=##class(Ens.Job).MakeNotQuiescent() If $$$ISERR(tSC) Quit
			Set tSC=$$$EnsError($$$EnsErrProductionNotQuiescent)
			$$$LOGINFO($$$FormatText($$$Text("Production failed to stop within timeout of %1 seconds."),pTimeout))
			Quit
		}
		Kill $$$EnsSuspendedAppData

		Set tSC=##class(Ens.Job).StopAll(pTimeout,pForce) If $$$ISERR(tSC) Quit
		Do ##class(Ens.Job).CleanUpDeadJobs()

		#; call OnProductionStop for each config item
		Set tConfigName="" For { Set tConfigName=$Order(tConfigNamesSaved(tConfigName),1,tClassname)  Quit:tConfigName=""
			$$$SetHostMonitor(tConfigName,$$$eMonitorStatus,"Stopped")
			try {
				Do $classmethod(tClassname,"OnProductionStop",tConfigName)
			} catch {
				If $ZE["<CLASS DOES NOT EXIST>" { $$$LOGERROR("Could not call OnProductionStop() on nonexistent class '"_$G(tClassName)_"'") }
				Else { Set tSC1=$$$SystemError  $$$LOGERROR("Error calling OnProductionStop(): "_$$$StatusDisplayString(tSC1)) }
			}
		}
		Do ..moveEnsRuntimeToEnsSuspended()
		Kill ^%SYS("Ensemble","RunningNamespace",$ZNspace)

		If $data($$$EnsSuspended)=1 {
			Kill $$$EnsSuspended
		}
		If $data($$$EnsJobStatus($$$SystemName))=1 {
			Kill $$$EnsJobStatus($$$SystemName)
		}
		If $data($$$EnsSuspended($$$SystemName)) {
			$$$LOGINFO($$$FormatText($$$Text("Production '%1' suspended."),tProductionName))
		} Else {
			$$$LOGINFO($$$FormatText($$$Text("Production '%1' stopped."),tProductionName))
		}
		Set tStopTime=$$$timeUTC
		Set ^Ens.Configuration("csp","Activity",tProductionName,"stopped")=tStopTime

		Do $classmethod(tProductionName,"OnStop",tStopTime,'tIsQuiescent)
		Set tSC2 = $$$AuditStartStopProduction(tProductionName,"stop") 
	} While 0
Exit
	Lock -$$$EnsRuntime
	Quit tSC
Trap
	Set $ZT="",tSC=$$$EnsSystemError
	Goto Exit
}

/// This method stops and restarts the running production.
/// pTimeout: How many seconds to wait for the jobs to go down.
/// pForce:   It indicates if we should forcefully kill the jobs which can not stop by themselves.
ClassMethod RestartProduction(pTimeout As %Numeric = 10, pForce As %Boolean = 0) As %Status
{
	Set $ZT="Trap",tSC=$$$OK
	Do {
		$$$LOGINFO($$$Text("RestartProduction initiated."))

		Lock +$$$EnsRuntime:30
		If '$Test Set tSC=$$$EnsError($$$EnsErrCanNotAcquireRuntimeLock,30) Quit

		Set tSC=..GetProductionStatus(.tProductionName,.tState) Quit:$$$ISERR(tSC)
		If tState'=$$$eProductionStateRunning {
			$$$LOGINFO($$$Text("No Production is running.")) Quit
		}
		
		// Call StopProduction()
		Set tSC = ..StopProduction(pTimeout, pForce) Quit:$$$ISERR(tSC)
		
		// Call StartProduction()
		Set tSC = ..StartProduction(tProductionName) Quit:$$$ISERR(tSC)
		
		$$$LOGINFO($$$Text("RestartProduction complete."))
		
	} While 0
Exit
	Lock -$$$EnsRuntime
	Quit tSC
Trap
	Set $ZT="",tSC=$$$EnsSystemError
	Goto Exit
}

ClassMethod moveEnsRuntimeToEnsSuspended()
{
	Tstart
	;
	Kill $$$EnsSuspended($$$SystemName)
	Set $$$EnsSuspended=$$$EnsRuntime("Name")
	;
	// put all active messages back to the queues
	Set tJob="" For  {
		Set tJob=$o($$$EnsActiveMessage(tJob),1,tId) Quit:tJob=""
		Set tSC=##class(Ens.Job).RecoverActiveMessage(tId,tJob,0)
		Kill $$$EnsActiveMessage(tJob)
	}
	// clean up the queue
	Set tQueueName="" For {
		Set tQueueName=$Order($$$EnsQueue(tQueueName))  Quit:tQueueName=""
		Lock +$$$EnsQueue(tQueueName):1 Else  Continue
		Kill $$$EnsQueue(tQueueName,0,"job")
		If (tQueueName?1.N)||($$$queueIsPrivateQueue(tQueueName)) {
			; can not save messages in private queues
			Set tPriority=0 For {
				Set tPriority=$Order($$$EnsQueue(tQueueName,tPriority)) Quit:tPriority=""
				Set tIndex="" For {
					Set tIndex=$Order($$$EnsQueue(tQueueName,tPriority,tIndex))  Quit:tIndex=""
					Set tId=$$$EnsQueue(tQueueName,tPriority,tIndex)
					Kill $$$EnsQueue(tQueueName,tPriority,tIndex)
					Set $$$EnsQueue(tQueueName,0,"count")=$$$EnsQueue(tQueueName,0,"count")-1
					Set pRequestHeader=##Class(Ens.MessageHeader).%OpenId(tId)
					If pRequestHeader'=$$$NULLOREF {
						$$$sysTRACE($$$FormatText($$$Text("Message '%1' in private queue '%2' has been discarded."),tId,tQueueName))
						Do pRequestHeader.SetStatus($$$eMessageStatusDiscarded)
					}
				}
			}
			Kill $$$EnsQueue(tQueueName)
		} Else {
			; can not save messages with high priorities
			Set tPriority=$$$eMessagePrioritySimSync For {
				Set tPriority=$Order($$$EnsQueue(tQueueName,tPriority),-1) Quit:tPriority=""  Quit:tPriority=0
				Set tIndex="" For {
					Set tIndex=$Order($$$EnsQueue(tQueueName,tPriority,tIndex))  Quit:tIndex=""
					Set tId=$$$EnsQueue(tQueueName,tPriority,tIndex)
					Kill $$$EnsQueue(tQueueName,tPriority,tIndex)
					Set $$$EnsQueue(tQueueName,0,"count")=$$$EnsQueue(tQueueName,0,"count")-1
					Set pRequestHeader=##Class(Ens.MessageHeader).%OpenId(tId)
					If pRequestHeader'=$$$NULLOREF Do pRequestHeader.SetStatus($$$eMessageStatusSuspended)
					$$$LOGWARNING("High priority message '"_tId_"' in queue '"_tQueueName_"' has been marked as suspended.")
				}
			}
			If $g($$$EnsQueue(tQueueName,0,"count"))<1 Kill $$$EnsQueue(tQueueName)
		}
		Lock -$$$EnsQueue(tQueueName)
	}
	If $data($$$EnsQueue) {
		Merge $$$EnsSuspended($$$SystemName,"Ens.Queue")=$$$EnsQueue
		Kill $$$EnsQueue
		$$$LOGWARNING("Queued messages are being saved in the suspended production.")
	}
	If $data($$$EnsAlarm) {
		Set tSC=##class(Ens.Alarm).SuspendAlarms()
		If $$$ISERR(tSC) {
			$$$LOGERROR("Error suspending Alarm Data: "_$$$StatusDisplayString(tSC))
			If $data($$$EnsAlarm) Merge $$$EnsSuspendedAppData("Ens.Alarm") = $$$EnsAlarm
		}
		Kill $$$EnsAlarm
		$$$LOGWARNING("Suspended Alarms are being saved in the suspended production.")
	}
	If $data($$$EnsSuspendedAppData) {
		Merge $$$EnsSuspended($$$SystemName,"AppData")=$$$EnsSuspendedAppData
		Kill $$$EnsSuspendedAppData
		$$$LOGWARNING("Suspended Application Data are being saved in the suspended production.")
	}
	;
	Kill $$$EnsRuntime
	Kill $$$EnsQueue
	Kill $$$EnsJobStatus($$$SystemName)
	Kill $$$EnsJobRequest
	;
	If $data($$$EnsSuspended($$$SystemName))=1 Kill $$$EnsSuspended($$$SystemName)
	;
	Tcommit
	;
	#;Cleanup scratch data
	Kill $$$EnsRuntimeAppData
	$$$KillAllHostMonitor
	$$$KillAllJobMonitor
	$$$KillAllLogMonitor
	;
	Quit
}

/// This method returns the production status via the output parameters.
/// pProductionName: Returns the production name when the status is running, suspended or troubled.
/// pState: Outputs production status. The valid values are:
///          $$$eProductionStateRunning
///          $$$eProductionStateStopped
///          $$$eProductionStateSuspended
///          $$$eProductionStateTroubled
ClassMethod GetProductionStatus(Output pProductionName As %String, Output pState As %Integer, pLockTimeout As %Numeric = 10) As %Status
{
	Set tSC=$$$OK
	Try {
		Set tIsMirrorBackup = 0
		#; If we are in a mirror and not the primary, determine whether the default database is mirrored
		If $system.Mirror.IsMember() && '$system.Mirror.IsPrimary() {
			Set tSC = ##class(%SYS.Ensemble).GlobalInMirroredDB($name($$$EnsRuntime),.tIsMirrorBackup)
			If $$$ISERR(tSC) Quit
		}
		If ('tIsMirrorBackup) {
			Lock +$$$EnsRuntime:pLockTimeout
			If '$Test {
				Set tSC=$$$ERROR($$$EnsErrCanNotAcquireRuntimeLock,pLockTimeout)
				Set pProductionName=""
				Set pState=$$$eProductionStateUnknown
				Quit
			}
			Set tLocked = 1
		}
		If ..IsProductionRunning() {
			Set pProductionName=$$$EnsRuntime("Name")
			Set pState=$select(tIsMirrorBackup: $$$eProductionStateBackupRunning, 1: $$$eProductionStateRunning)
			Quit
		}
		If ('$data($$$EnsJobStatus))&&('$data($$$EnsRuntime))&&('$data($$$EnsSuspended)) {
			Set pProductionName=""
			Set pState=$select(tIsMirrorBackup: $$$eProductionStateBackupStopped, 1: $$$eProductionStateStopped)
			Quit
		}
		If ('$data($$$EnsJobStatus))&&('$data($$$EnsRuntime))&&($data($$$EnsSuspended)) {
			Set pProductionName=$get($$$EnsSuspended)
			Set pState=$select(tIsMirrorBackup: $$$eProductionStateBackupSuspended, 1: $$$eProductionStateSuspended)
			Quit
		}
		If ('$data($$$EnsJobStatus($$$SystemName)))&&('$data($$$EnsRuntime("System",$$$SystemName)))&&($data($$$EnsRuntime("System"))) {
			Set pProductionName=$get($$$EnsRuntime("Name"))
			Set pState=$select(tIsMirrorBackup: $$$eProductionStateBackupNetworkStopped, 1: $$$eProductionStateNetworkStopped)
			Quit
		}
		Set pProductionName=$get($$$EnsRuntime("Name"),$get($$$EnsSuspended))
		Set pState=$select(tIsMirrorBackup: $$$eProductionStateBackupUnknown, 1: $$$eProductionStateTroubled)
	}
	Catch {
		Set tSC = $$$EnsSystemError
	}
	If $get(tLocked) Lock -$$$EnsRuntime
	Quit tSC
}

/// This method returns whether a production is currently running in this namespace.
/// Note that this method is not as reliable as <method>GetProductionStatus</method>() as it does
/// not lock $$$EnsRuntime and may not accurately reflect the production status while the production
/// is changing state, e.g. while starting or stopping.
ClassMethod IsProductionRunning() As %Boolean [ CodeMode = expression ]
{
($data($$$EnsJobStatus($$$SystemName)))&&($data($$$EnsRuntime("System",$$$SystemName)))&&($$$EnsRuntime("CheckSum")=$get(^%SYS("Ensemble","RunningNamespace",$namespace)))
}

/// This method returns a boolean to indicate if the running production needs to be updated or not.
/// pReason: is an output parameter that gives detailed reasons.
ClassMethod ProductionNeedsUpdate(Output pReason As %String) As %Boolean
{
	Set $ZT="Trap",pReason="",tNeedsUpdate=0
	Do {
		Lock +$$$EnsRuntime:30
		If '$Test Set pReason=$system.Status.GetErrorText($$$EnsError($$$EnsErrCanNotAcquireRuntimeLock,30)) Quit

		Set tProductionName=$g($$$EnsRuntime("Name")) If tProductionName="" set pReason="No production is running." Quit
		Do ..findProductionDifferences(tProductionName,0,,.tToStopJob,.tToStartConfig,.tToDeleteConfig,.tToUpdateScheduler,.tToCleanJobStatus)
		Set j="" For  {
			Set j=$o(tToCleanJobStatus(j)) Quit:j=""
			Set pReason=pReason_"Job "_$p($e(j,2,*),"_",1)_", which ran '"_$$$EnsJobStatus($$$SystemName,j,$$$eJobStartConfigName)_"' has died."_$c(13,10)
			Set tNeedsUpdate=0
		}
		Set j="" For  {
			Set j=$o(tToStopJob(j),1,tIsTemp) Quit:j=""  Continue:tIsTemp<0
			Set pReason=pReason_"Job "_j_" needs to be terminated."_$c(13,10)
			Set tNeedsUpdate=1
		}
		Set c="" For  {
			Set c=$o(tToStartConfig(c)) Quit:c=""  
			Set pReason=pReason_tToStartConfig(c)_" new job"_$s(tToStartConfig(c)=1:"",1:"s")_" for config item '"_c_"' need"_$s(tToStartConfig(c)=1:"s",1:"")_" to be started."_$c(13,10)
			Set tNeedsUpdate=1
		}
		Set c="" For  {
			Set c=$o(tToDeleteConfig(c)) Quit:c=""
			Set pReason=pReason_"Registration for config item '"_c_"' needs to be deleted."_$c(13,10)
			Set tNeedsUpdate=1
		}
		If tToUpdateScheduler {
			Set pReason=pReason_"Scheduler needs to be updated."_$c(13,10)
			Set tNeedsUpdate=1
		}
	} While 0
Exit
	Lock -$$$EnsRuntime
	Quit tNeedsUpdate
Trap
	Set $ZT="",tSC=$$$EnsSystemError,pReason="Internal Error Encountered.",tNeedsUpdate=0
	Goto Exit
}

/// This method recovers the last running production whose status is eProductionStateTroubled.
ClassMethod RecoverProduction() As %Status
{
	Set $ZT="Trap",tSC=$$$OK
	Do {
		Lock +$$$EnsRuntime:30
		If '$Test Set tSC=$$$EnsError($$$EnsErrCanNotAcquireRuntimeLock,30) Quit
		
		Set tSC=..GetProductionStatus(.tProductionName,.tState) Quit:$$$ISERR(tSC)
		If tState'=$$$eProductionStateTroubled {
			$$$sysTRACE($$$Text("Nothing to recover.")) Quit
		}
		Do ..moveEnsRuntimeToEnsSuspended()
		$$$sysTRACE($$$Text("Production recovery finished.")) Quit
	} While 0
Exit
	Lock -$$$EnsRuntime
	Quit tSC
Trap
	Set $ZT="",tSC=$$$EnsSystemError
	Goto Exit
}

ClassMethod findProductionDifferences(pProductionName As %String, pLog As %Boolean, Output pDefinition, Output pToStopJob, Output pToStartConfig, Output pToDeleteConfig, Output pToUpdateScheduler As %Boolean = 0, Output pToCleanJobStatus, Output pActorForceDisabled As %Boolean = 0) As %Status
{
	Set $ZT="Trap",tSC=$$$OK
	Do {
		Set tProduction = ##class(Ens.Config.Production).%OpenId(pProductionName,,.tSC)
		If '$IsObject(tProduction)||$$$ISERR(tSC) { Set tSC=$$$EnsError($$$EnsErrProductionNotRegistered,pProductionName,$$$StatusDisplayString(tSC))  Quit }

		#; Set a special node for unaffiliated Trace event logging; the Trace macros look for this by default
		Set pDefinition("%Production","Trace")=tProduction.LogGeneralTraceEvents
		Set tSC = tProduction.PopulateModifiedSettings()
		Set tIndex="" For { Set tIndex = tProduction.ModifiedSettings.Next(tIndex)  Quit:tIndex=""
			Set tSetting = tProduction.ModifiedSettings.GetAt(tIndex)
			Set pDefinition("%Production","Setting",tSetting.Name)=tSetting.Value
		}
		Set pDefinition("%Production","Checksum")=tProduction.Checksum() ; depends on PopulateModifiedSettings()

		Set tAutoAdd("Ens.Alarm")=1
		Set tAutoAdd("Ens.Actor")=1
		Set tAutoAdd("Ens.MonitorService")=1
		Set tAutoAdd("EnsLib.Testing.Service")=1
		Set tAutoAdd("EnsLib.Testing.Process")=1
		Set tAutoAdd("Ens.ScheduleHandler")=1
		Set tAutoAdd("Ens.ScheduleService")=1
		For i=tProduction.Items.Count():-1:1 { Set tConfigName = tProduction.Items.GetAt(i).Name
			If $data(tAutoAdd(tConfigName)) Set tAutoAdd(tConfigName)=0
		}
		Set tConfigName="Ens.Alarm"
		If tAutoAdd(tConfigName) {
			Set pDefinition(tConfigName)=""
			Set pDefinition(tConfigName,"IsEnabled")=1
			Set pDefinition(tConfigName,"ClassName")=tConfigName
			Set pDefinition(tConfigName,"OnTaskClassName")=tConfigName
			Set pDefinition(tConfigName,"QueueName")=tConfigName
			Set pDefinition(tConfigName,"PoolSize")=1
			Set pDefinition(tConfigName,"Foreground")=0
			Set pDefinition(tConfigName,"DisableErrorTraps")=0
			Set pDefinition(tConfigName,"BusinessType")=$$$eHostTypeOperation
			Set pDefinition(tConfigName,"InactivityTimeout")=0
			Set pDefinition(tConfigName,"Checksum")=""
			Set pDefinition(tConfigName,"Register")=1
			Set pDefinition(tConfigName,"RunAsJob")=1
			Set pDefinition(tConfigName,"Trace")=0
		}
		Set tConfigName="Ens.Actor"
		If tAutoAdd(tConfigName) {
			Set pActorForceDisabled=..hasDisabledActorProcess(tProduction)
			Set pDefinition(tConfigName)=""
			Set pDefinition(tConfigName,"IsEnabled")='pActorForceDisabled
			Set pDefinition(tConfigName,"ClassName")=tConfigName
			Set pDefinition(tConfigName,"OnTaskClassName")=tConfigName
			Set pDefinition(tConfigName,"QueueName")=tConfigName
			Set pDefinition(tConfigName,"PoolSize")=tProduction.ActorPoolSize
			Set pDefinition(tConfigName,"Foreground")=tProduction.ActorDebugSetting("Foreground")
			Set pDefinition(tConfigName,"DisableErrorTraps")=tProduction.ActorDebugSetting("DisableErrorTraps")
			Set pDefinition(tConfigName,"BusinessType")=$$$eHostTypeActor
			Set pDefinition(tConfigName,"InactivityTimeout")=60
			Set pDefinition(tConfigName,"Checksum")=""
			Set pDefinition(tConfigName,"Register")=0
			Set pDefinition(tConfigName,"RunAsJob")='pActorForceDisabled
			Set pDefinition(tConfigName,"Trace")=0
		}
		Set tConfigName="Ens.MonitorService"
		If tAutoAdd(tConfigName) {
			Set pDefinition(tConfigName)=""
			Set pDefinition(tConfigName,"IsEnabled")=1
			Set pDefinition(tConfigName,"ClassName")=tConfigName
			Set pDefinition(tConfigName,"OnTaskClassName")=tConfigName
			Set pDefinition(tConfigName,"QueueName")=tConfigName
			Set pDefinition(tConfigName,"PoolSize")=1
			Set pDefinition(tConfigName,"Foreground")=0
			Set pDefinition(tConfigName,"DisableErrorTraps")=0
			Set pDefinition(tConfigName,"BusinessType")=$$$eHostTypeService
			Set pDefinition(tConfigName,"InactivityTimeout")=0
			Set pDefinition(tConfigName,"Checksum")=""
			Set pDefinition(tConfigName,"Register")=1
			Set pDefinition(tConfigName,"RunAsJob")=1
			Set pDefinition(tConfigName,"Trace")=0
		}
		Set tConfigName="Ens.ScheduleHandler"
		If tAutoAdd(tConfigName) {
			Set pDefinition(tConfigName)=""
			Set pDefinition(tConfigName,"IsEnabled")=1
			Set pDefinition(tConfigName,"ClassName")=tConfigName
			Set pDefinition(tConfigName,"OnTaskClassName")="Ens.Actor"
			Set pDefinition(tConfigName,"QueueName")=tConfigName
			Set pDefinition(tConfigName,"PoolSize")=1
			Set pDefinition(tConfigName,"Foreground")=0
			Set pDefinition(tConfigName,"DisableErrorTraps")=0
			Set pDefinition(tConfigName,"BusinessType")=$$$eHostTypeProcess
			Set pDefinition(tConfigName,"InactivityTimeout")=0
			Set pDefinition(tConfigName,"Checksum")=""
			Set pDefinition(tConfigName,"Register")=1
			Set pDefinition(tConfigName,"RunAsJob")=1
			Set pDefinition(tConfigName,"Trace")=0
		}
		Set tConfigName="Ens.ScheduleService"
		If tAutoAdd(tConfigName) {
			Set pDefinition(tConfigName)=""
			Set pDefinition(tConfigName,"IsEnabled")=1
			Set pDefinition(tConfigName,"ClassName")=tConfigName
			Set pDefinition(tConfigName,"OnTaskClassName")=tConfigName
			Set pDefinition(tConfigName,"QueueName")=tConfigName
			Set pDefinition(tConfigName,"PoolSize")=0
			Set pDefinition(tConfigName,"Foreground")=0
			Set pDefinition(tConfigName,"DisableErrorTraps")=0
			Set pDefinition(tConfigName,"BusinessType")=$$$eHostTypeService
			Set pDefinition(tConfigName,"InactivityTimeout")=0
			Set pDefinition(tConfigName,"Checksum")=""
			Set pDefinition(tConfigName,"Register")=1
			Set pDefinition(tConfigName,"RunAsJob")=0
			Set pDefinition(tConfigName,"Trace")=0
		}
		If tProduction.TestingEnabled {
			Set tConfigName="EnsLib.Testing.Service"
			If tAutoAdd(tConfigName) {
				Set pDefinition(tConfigName)=""
				Set pDefinition(tConfigName,"IsEnabled")=1
				Set pDefinition(tConfigName,"ClassName")=tConfigName
				Set pDefinition(tConfigName,"OnTaskClassName")=tConfigName
				Set pDefinition(tConfigName,"QueueName")=tConfigName
				Set pDefinition(tConfigName,"PoolSize")=0
				Set pDefinition(tConfigName,"Foreground")=0
				Set pDefinition(tConfigName,"DisableErrorTraps")=0
				Set pDefinition(tConfigName,"BusinessType")=$$$eHostTypeService
				Set pDefinition(tConfigName,"InactivityTimeout")=0
				Set pDefinition(tConfigName,"Checksum")=""
				Set pDefinition(tConfigName,"Register")=1
				Set pDefinition(tConfigName,"RunAsJob")=0
				Set pDefinition(tConfigName,"Trace")=0
			}
			Set tConfigName="EnsLib.Testing.Process"
			If tAutoAdd(tConfigName) {
				Set pDefinition(tConfigName)=""
				Set pDefinition(tConfigName,"IsEnabled")=1
				Set pDefinition(tConfigName,"ClassName")=tConfigName
				Set pDefinition(tConfigName,"OnTaskClassName")="Ens.Actor"
				Set pDefinition(tConfigName,"QueueName")=tConfigName
				Set pDefinition(tConfigName,"PoolSize")=1
				Set pDefinition(tConfigName,"Foreground")=0
				Set pDefinition(tConfigName,"DisableErrorTraps")=0
				Set pDefinition(tConfigName,"BusinessType")=$$$eHostTypeProcess
				Set pDefinition(tConfigName,"InactivityTimeout")=0
				Set pDefinition(tConfigName,"Checksum")=""
				Set pDefinition(tConfigName,"Register")=1
				Set pDefinition(tConfigName,"RunAsJob")=1
				Set pDefinition(tConfigName,"Trace")=0
			}
		}
		#; get production items
		Set tSC=..getProductionItems(tProduction,.pDefinition,.tAutoAdd)
		Quit:$$$ISERR(tSC)
		#; count running jobs for each config item
		Do ##class(Ens.Job).MarkDeadJobs()
		Lock +$$$EnsJobStatus($$$SystemName):2  Else  Set tSC=$$$EnsError($$$EnsErrCanNotAcquireJobRootLock,2) Quit
		Set tJob="" For { Set tJob=$Order($$$EnsJobStatus($$$SystemName,tJob))  Quit:tJob=""
			Continue:$G($$$EnsJobStatus($$$SystemName,tJob,$$$eJobIsDead))
			Set tIsTemp=$G($$$EnsJobStatus($$$SystemName,tJob,$$$eJobIsTempJob))
			Set tJobConfigName=$G($$$EnsJobStatus($$$SystemName,tJob,$$$eJobStartConfigName),"<unknown ConfigItem>")
			Set tRunningConfig(tJobConfigName,tJob)=tIsTemp
			Set:'tIsTemp tRunningJobCount(tJobConfigName)=$G(tRunningJobCount(tJobConfigName))+1
		}
		Lock -$$$EnsJobStatus($$$SystemName)
		#; flag any change in production settings
		If pDefinition("%Production","Checksum")'=$G($$$ConfigChecksum("%Production")) {
			Set pToUpdateScheduler=1
		}
		#; build counts of item jobs to start and list of jobs to stop
		Set tConfigName="" For { Set tConfigName=$Order(pDefinition(tConfigName))  Quit:tConfigName=""  Continue:tConfigName="%Production"
			Set tClassName=pDefinition(tConfigName,"ClassName"), tBusinessType=pDefinition(tConfigName,"BusinessType")
			If '##class(%Dictionary.ClassDefinition).%ExistsId(tClassName)   { Set tSC1=$$$EnsError($$$EnsErrGeneral,"Class "_tClassName_" does not exist for Config Item "_tConfigName), pDefinition(tConfigName,"RunAsJob")=0 }
			ElseIf '##class(%Dictionary.CompiledClass).%ExistsId(tClassName) { Set tSC1=$$$EnsError($$$EnsErrGeneral,"Class "_tClassName_" is not compiled for Config Item "_tConfigName), pDefinition(tConfigName,"RunAsJob")=0 }
			ElseIf tBusinessType=$$$eHostTypeUnknown { Set tSC1=$$$EnsError($$$EnsErrGeneral,"Config Item "_tConfigName_" cannot run because it has unknown BusinessType"), pDefinition(tConfigName,"RunAsJob")=0 }
			Else { Set tSC1=$$$OK }
			Set:$$$ISERR(tSC1) tSC=$$$ADDSC(tSC,tSC1)

			Set tEffectivePoolSize=$Case(pDefinition(tConfigName,"RunAsJob"), 0:0, -1:1, :pDefinition(tConfigName,"PoolSize"))
			If pDefinition(tConfigName,"Register")&&'$D($$$ConfigRoot(tConfigName)) {
				Set pToStartConfig(tConfigName)=tEffectivePoolSize
				Set tToStopConfig(tConfigName)=""
				If pLog $$$SysWebTrace($$$FormatText($$$Text("%1: new item to be started."),tConfigName))
				Set pToUpdateScheduler=1
			} ElseIf pDefinition(tConfigName,"Checksum")'=$G($$$ConfigChecksum(tConfigName)) {
				Set pToStartConfig(tConfigName)=tEffectivePoolSize
				Set pToStartConfig(tConfigName,"update")=""
				Set tToStopConfig(tConfigName)=""
				If pLog $$$SysWebTrace($$$FormatText($$$Text("%1: modified item to be updated."),tConfigName))
				Set pToUpdateScheduler=1
				Continue
			} Else {
				If +$G(tRunningJobCount(tConfigName))'=tEffectivePoolSize {
					#; Actual PoolSize may be nonzero even if RunAsJob=0. For example the PoolSize of an adapterless Service or a JobPerConnection
					#;  Service may be used to limit on the number of externally invoked Service jobs allowed to run at one time
					#; RunAsJob=-1 means run only 1 job regardless of PoolSize, e.g. for TCP.InboundAdapter
					Set pToStartConfig(tConfigName)=tEffectivePoolSize-$G(tRunningJobCount(tConfigName))
					Set pToStartConfig(tConfigName,"update")=""
					If pLog {
						If pToStartConfig(tConfigName)>0 {
							$$$SysWebTrace($$$FormatText($$$Text("%1: poolsize to be increased by %2."),tConfigName,pToStartConfig(tConfigName)))
						} Else {
							$$$SysWebTrace($$$FormatText($$$Text("%1: poolsize to be decreased by %2."),tConfigName,-pToStartConfig(tConfigName)))
						}
					}
				}
				Set:$G(pDefinition(tConfigName,"Schedule"))'=$g($$$ConfigSchedule(tConfigName)) pToUpdateScheduler=1
			}
		}
		Set tLiveConfigName="" For { Set tLiveConfigName=$Order($$$ConfigRoot(tLiveConfigName))  Quit:tLiveConfigName=""  Continue:tLiveConfigName="%Production"
			Continue:$D(pDefinition(tLiveConfigName))
			Set tToStopConfig(tLiveConfigName)=""
			Set pToDeleteConfig(tLiveConfigName)=""
			If pLog $$$SysWebTrace($$$FormatText($$$Text("%1: deleted item to be stopped."),tLiveConfigName))
			Set:$G(pDefinition(tLiveConfigName,"Schedule"))'=$g($$$ConfigSchedule(tLiveConfigName)) pToUpdateScheduler=1

		}
		Set tConfigName="" For { Set tConfigName=$Order(tRunningConfig(tConfigName))  Quit:tConfigName=""
			Set tJob="" For { Set tJob=$Order(tRunningConfig(tConfigName,tJob),1,tIsTemp)  Quit:tJob=""
				If $G(pToStartConfig(tConfigName))<0 {
					// !!! only if not an active Operation
					Set pToStopJob(tJob)=tIsTemp
					Set:'tIsTemp pToStartConfig(tConfigName)=pToStartConfig(tConfigName)+1
					Kill:'pToStartConfig(tConfigName) pToStartConfig(tConfigName)
				}
				ElseIf $Data(tToStopConfig(tConfigName)) {
					Set pToStopJob(tJob)=tIsTemp
				}
			}
		}
		// !!! stop more Operation jobs if needed, even if they
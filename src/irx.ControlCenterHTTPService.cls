Number of args=2,pull,irx.ControlCenterHTTPService.cls,
Class irx.ControlCenterHTTPService Extends Ens.BusinessService
{

// Parameter ADAPTER = "EnsLib.HTTP.InboundAdapter";

Method OnProcessInput(input:irx.Request,*output:%ZEN.proxyObject) As %Status 
 {
	#dim exception as %Exception.AbstractException
	try {
		set output=##class(%ZEN.proxyObject).%New()
		set output.action = input.Action_"_response"
		set output.timestamp = $zdt($h,-2)
		set output.controlId = input.ControlId
		// send off to Async process
		Set sc = ..SendRequestAsync("irx.ControlCenterMessageProcessor",input) 
		if $$$ISERR(sc) throw ##class(%Exception.StatusException).CreateFromStatus(sc)
	} catch (exception) {
		Do exception.Log()
		return exception.AsStatus()
	}
	return $$$OK
 }

}

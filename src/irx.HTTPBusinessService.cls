Number of args=2,pull,irx.HTTPBusinessService.cls,
Class irx.HTTPBusinessService Extends Ens.BusinessService
{

Parameter ADAPTER    = "EnsLib.HTTP.InboundAdapter";

Method OnProcessInput(request:%CSP.Request,*response:%CSP.Response) As %Status 
 {
	#dim exception As %Exception.General
	Set sc=$$$OK
	set response = ##class(%CSP.Response).%New()
	set response.ContentType = "application/json"
	try {
		
		set response.Status="200 OK"
	} catch (exception) {
		do exception.Log()
		
		set response.Status="500 Internal Server Error"
	}
	Quit sc
 }

}

/// CSP class to process messages from iRx Control Center into HealthShare. 
/// This class also contains logic to send messages from HealthShare to iRx.
/// All communication between the systems is handled here
Class irx.ControlCenter Extends %CSP.Page
{

Parameter CONTENTTYPE    = "application/json";

/// Load up some configuration parameters from 
/// a control global
ClassMethod loadParameters(*params)  
 {
	merge params=^irx.Control("p")
	return
 }

Parameter pBusinessService    = "BusinessService";

Parameter piRxControlCenterEndpoint    = "iRxControlCenterEndpoint";

Parameter piRxControlCenterSSL   ;

ClassMethod loadTestParameters()  
 {
	// the name of the business service to fire request off to
	set ^irx.Control("p","BusinessService")="irx.ens.ControlCenterService"
	// the url of the service to send messsages back to iRx
	// for production something like this:
	//set ^irx.Control("p","iRxControlCenterEndpoint")="http://server:1234/HealthShareControl"
	
	// for testing - something like this
	set ns="csp/"_$namespace
	set ^irx.Control("p","iRxControlCenterEndpoint")="http://localhost:57774/"_ns_"/irx.MockControlCenter.cls"
	
	// the SSL config to use, if any
	set ^irx.Control("p","iRxControlCenterSSL")=""
 }

ClassMethod ValidateRequest(reqId:%Integer,*po:%ZEN.proxyObject)  
 {
	#dim %request As %CSP.Request
	set method = %request.Method
	if ( method '= "POST" ) {
				throw ..exp("Unsupported HTTP method '"_method_"'")
	}
	if ( %request.ContentType '= "application/json" ) {
			throw ..exp("Unsupported content type:"_%request.ContentType)
	}
	
	set body = %request.Content
	if ( ('$isobject(body)) && ($get(%request.CgiEnvs("HTTP_"_..#IRXCONTROL),"")'="") ) {
			set po=##class(%ZEN.proxyObject).%New()
			set ^irx.ControlCenter(reqId,"i")=""
			return
	}
	// Don't allow empty body unless it's a control request
	if ( body.Size = 0 ) {
		
		
		throw ..exp("Empty request content")
	}
	do body.Rewind()
	set json=""
	while ( 'body.AtEnd ) {
		set json=json_body.ReadLine()
	}
	set ^irx.ControlCenter(reqId,"i")=json
	set sc = ##class(%ZEN.Auxiliary.jsonProvider).%ConvertJSONToObject(json,,.po)
	throw:$$$ISERR(sc) ##class(%Exception.StatusException).CreateFromStatus(sc)
 }

ClassMethod exp(msg:%String) As %Exception.General 
 {
	set e=##class(%Exception.General).%New("irx.ControlCenterException")
	set e.Code = "irx"
	set e.Data = msg
	return e
 }

/// Message can be just JSON or a proxyObject
ClassMethod SendToControlCenter(message)  
 {
	if ( $isobject(message) ) {
		if ( $classname(message) '= "%ZEN.proxyObject" ) {
			throw ..exp("message type was "_$classname(message)_" but %ZEN.proxyObject or string is required")
		}
		
		set jstream=##class(%Stream.TmpCharacter).%New()
		set sc=##class(%ZEN.Auxiliary.jsonProvider).%WriteJSONStreamFromObject(jstream,message,,1,"i")
		//do jstream.Rewind()
		set msg=jstream.ReadLine()
		while ( 'jstream.AtEnd ) {
			set msg=msg_jstream.ReadLine()
		}
		set message = msg		
	} 
	do ..loadParameters(.params)
	set ccurl=params(..#piRxControlCenterEndpoint)
	set req=##class(%Net.HttpRequest).%New()
	do ##class(%Net.URLParser).Parse(ccurl,.url)
	set req.Server=url("host")
	set req.Port=$get(url("port"),80)
	if ( ..#piRxControlCenterSSL '= "" ) {
		set req.SSLConfiguration = params(..#piRxControlCenterSSL)
		set req.Https=1
	}
	// TODO - add user/password ??
	set req.Username="_system",req.Password="SYS"
	set req.ContentType="application/json"
	do req.EntityBody.Write(..QuoteJS(message))
	set sc=req.Post(url("path"),2)
 }

/// Meta actions - 
/// ECHO 		just return the requst
/// LOG<X>		return last <X> requests, where X is some int between 0 and 100 - or LOG default to 10
/// FLUSH		kill off ^irx.ControlCenter global
/// ...
/// CONFIG		read config parameters from JSON request body, or if body empty return current confif
/// TEST		Render a human UI to test the system?? TO-DO
ClassMethod ProcessMetaAction(action,reqId,&po:%ZEN.proxyObject)  
 {
	set action=$zconvert(action,"U")
	if ( action = "ECHO" ) {
		do po.%CopyToArray(.poa)
		merge ^irx.ControlCenter(reqId,"o")=poa
		return
	}
	if ( action = "TEST" ) {	// send the messsage off to the MockControlCenter
		set response=..SendToControlCenter(po)
		set ^irx.ControlCenter(reqId,"o","status")="Sent to MockControlCenter"
		set ^irx.ControlCenter(reqId,"o","response")=response
		
		return
	}
	if ( action = "FLUSH" ) {
		kill ^irx.ControlCenter
		return
	}
	if ( action ? 1"LOG".N ) { 	// return log
		//set ^irx.ControlCenter(reqId,"o","status")="NOT IMPLEMENTED YET"
		/**/
		set n=$piece(action,"LOG",2)
		//break
		if ( n="" ) { set n=$s(^irx.ControlCenter("reqId")>10:10,1:^irx.ControlCenter("reqId")) }
		set log=##class(%ZEN.proxyObject).%New()
		set log.requests=##class(%Library.ListOfObjects).%New()
		set count=0
		//for i=^irx.ControlCenter("reqId"):-1:^irx.ControlCenter("reqId")-(n-1) {
		//	continue:i=reqId	// don't log yourself
		set i=$order(^irx.ControlCenter(^irx.ControlCenter("reqId")),-1)
		while ( i'="" ) {
			continue:$get(^irx.ControlCenter(reqId,"o_/\_c"),0)=1
			set count=count+1
			quit:(count>=n)
			set ^||irx.ControlCenter(reqId,"o",count,"reqId")=i
			if ( $data(^irx.ControlCenter(i,"i") )) {
				merge ^||irx.ControlCenter(reqId,"o",count,"i")=^irx.ControlCenter(i,"i")
			}
			if ( $data(^irx.ControlCenter(i,"o") )) {
				merge ^||irx.ControlCenter(reqId,"o",count,"o")=^irx.ControlCenter(i,"o")
			}
			set i=$order(^irx.ControlCenter(i),-1)
		}
		// signal complex response
		set ^irx.ControlCenter(reqId,"o_/\_c")=1
		/**/
		return
	}
	if ( action = "CONFIG" ) {
		// any body? - if so update
		/*
		if ( $data(^irx.ControlCenter(reqId,"i")) = 11 ) {
			// validate params !!!
			merge ^irx.Control("p")=^irx.ControlCenter(reqId,"i")
		}
		*/
		merge ^irx.ControlCenter(reqId,"o")=^irx.Control("p")
		return
	}
	throw ..exp("Unsupported "_..#IRXCONTROL_" action '"_action_"'")
 }

Parameter IRXCONTROL    = "IRX_CONTROL";

// note CSP will rewrite -'s to _'s!

Parameter HSCONTROL    = "HS-CONTROL";

ClassMethod ProcessRequest(reqId:%Integer,&po:%ZEN.proxyObject) As %Integer 
 {
	
	merge ^cgi=%request.CgiEnvs
	set metaAction = $get(%request.CgiEnvs("HTTP_"_..#IRXCONTROL),"")
	if ( metaAction '= "" ) {
		do %response.SetHeader(..#HSCONTROL,metaAction_"_response")
		do ..ProcessMetaAction(metaAction, reqId, .po)
		return
	}
	// depending on the request - fire off to ensemble
	//set action=po.action
	//set po=##class(%ZEN.proxyObject).%New()
	//set po.action = action_"_response"
	set po.controlId = %response.GetHeader("ControlId")
	// -2 converts between unix epoch and cache time
	// $zdt($zdatetimeh("1369236083",-2),-2)
	set po.timestamp = $zdt($h,-2)	// return current system time in unix format
	// serialize to global
	//set poj = ##class(%ZEN.Auxiliary.jsonProvider).%WriteJSONFromObject(.po)
	set sc=##class(Ens.Director).CreateBusinessService("irx.ControlCenterHTTPService",.service)
	if ($$$ISERR(sc)) throw ##class(%Exception.StatusException).CreateFromStatus(sc)
	set request=##class(irx.Request).createFromCSPRequest(%request)
	set request.Action = po.action
	set sc=service.ProcessInput(request,.output)
	if ($$$ISERR(sc)) throw ##class(%Exception.StatusException).CreateFromStatus(sc)
	do output.%CopyToArray(.outputa)
	merge ^irx.ControlCenter(reqId,"o")=outputa
	return reqId
 }

ClassMethod GetResponse(reqId:%Integer,*response)  
 {
	
	
		
	// not a complex response - like with an array
	if ( '$get(^irx.ControlCenter(reqId,"o_/\_c"),0) ) {
		merge response = ^irx.ControlCenter(reqId,"o")
		return 0
	} else {
		merge response = ^||irx.ControlCenter(reqId,"o")
		return 1  //signal that response is not a simple json guy
	}
		
	
	//kill ^irx.ControlCenter(reqId)
 }

ClassMethod OnPreHTTP() As %Boolean 
 {
	#dim exp As %Exception.General
	set ok=1
	// validate we have a good message
	try {
		set reqId=$increment(^irx.ControlCenter("reqId"))
		set controlId=$namespace_";"_$system.Util.CreateGUID()
		do %response.SetHeader("ControlId",controlId)
		do ..ValidateRequest(reqId,.jsonRequest)
		do ..ProcessRequest(reqId,.jsonRequest)
		do %response.SetHeader("RequestId",reqId)
	} catch (exp) {
		do exp.Log()
		set %response.Status = "500 Internal Server Error"
		do %response.SetHeader("Error",exp.DisplayString())
		set ok=0	// no OnPage
	}
	Quit ok
 }

ClassMethod OnPage() As %Status 
 {
	#dim exp As %Exception.General
	try {
		Set reqId = %response.GetHeader("RequestId")
		set complex=..GetResponse(reqId,.responseData)
		if ( 'complex) {
			set responsePO = ##class(%ZEN.proxyObject).%New()
			do responsePO.%CopyFromArray(.responseData)
			set responsePO.ControlId=%response.GetHeader("ControlId")
			do ##class(%ZEN.Auxiliary.jsonProvider).%ObjectToJSON(responsePO)
		} else { // complex response - 
			
			zw responseData
		}
		
	} catch(exp) {
		set r=..jsonException(exp)
		&html< #(r)#>
	}
	
	Quit $$$OK
 }

ClassMethod jsonException(&exp:%Exception.AbstractException) As %String 
 {
	set r="{""Error"":"""_..QuoteJS(exp.DisplayString())_"""}"
	return r
 }

}

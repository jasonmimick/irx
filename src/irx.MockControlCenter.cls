Number of args=2,pull,irx.MockControlCenter.cls,
/// Fake control center endpoint to which we can send messages from Ensemble
Class irx.MockControlCenter Extends %CSP.Page
{

Parameter CONTENTTYPE    = "application/json";

ClassMethod StoreMessage()  
 {
	set body = %request.Content
	if ( $isobject(body) && body.Size=0 ) 	{
		throw ##class(%Exception.General).%New("iRx.MockControlCenter","ERROR",,"No content found")
	}
	do body.Rewind()
	set json=""
	while ( 'body.AtEnd ) {
		set json=json_body.ReadLine()
	}
	set i=$i(^irx.MockControlCenter)
	set ^irx.MockControlCenter(i)=json
	return i
	//return "{ ""status"" : ""ok"" }"
 }

ClassMethod OnPreHTTP() As %Boolean 
 {
	#dim exp As %Exception.AbstractException
	if ( %request.Method = "POST" ) {
		try {
			set i=..StoreMessage()
			do %response.SetHeader("ControlCenter","OK")
			do %response.SetHeader("ControlCenterIn",^irx.MockControlCenter(i))
		} catch (exp) {
			set %response.Status = "500 Internal Server Error"
			do %response.SetHeader("Error",exp.DisplayString())
		}
		Quit 0		// no body in response - just write headers	
	}
	set %response.ContentType="text/html"
	Quit 1
 }

ClassMethod OnPage() As %Status 
 {
	// Accept POST messages and log them.
	
	// If GET then dump out the message we've stored to the browser
	&html<<html>
	<head>
	<title>Mock iRx Control Center</title>
	</head>
	
		
	<body>>
	if ( %request.Get("flush")=1 ) {
		Kill ^iRx.MockControlCenter
		&html< <h2>Flushed MockControlCenter messages</h2> >
	}	
	&html<
	<pre>>
	zw ^irx.MockControlCenter
	&html<</pre>
	</body>
	</html>>
	Quit $$$OK
 }

}

Number of args=2,pull,irx.Request.cls,
Class irx.Request Extends Ens.Request
{

Property Action As %String;

Property Headers As list of %String;

Index ControlId On ControlId;

Property Body As %String(MAXLEN=5000);

Property ControlId As %String;

ClassMethod createFromCSPRequest(&req:%CSP.Request,save:%Boolean=0) As irx.Request 
 {
	set me=..%New()
	set me.ControlId=$namespace_";"_$system.Util.CreateGUID()

	set me.Headers=$listbuild()
	for header="IRX_CONTROL","API-KEY" {
		set me.Headers=me.Headers_$listbuild(header,$get(req.CgiEnvs("HTTP_"_header),""))
	}

	set body=req.Content		
	if ( $isobject(body) ) {
		do body.Rewind()
		set me.Body=body.ReadLine()
		while ( 'body.AtEnd ) {
			set me.Body=me.Body_body.ReadLine()
		}
	}
	if ( save ) {
		set sc=me.%Save()
		throw:$$$ISERR(sc) ##class(%Exception.StatusException).CreateFromStatus(sc)
	}	
	return me
 }

}

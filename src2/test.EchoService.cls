class test.EchoService extends EnsLib.HTTP.Service [ ProcedureBlock ]
{

Parameter ADAPTER = "EnsLib.HTTP.InboundAdapter";

Method OnProcessInput(pInput As %Library.AbstractStream, Output pOutput As %Stream.Object) As %Status
{
	try {
		merge ^test.EchoService("Attributes")=pInput.Attributes
		Set pOutput=##class(%GlobalBinaryStream).%New()
		do pOutput.WriteLine("-- Attributes --")
		set key=$order(pInput.Attributes(""))
		while ( key'="" ) {
			do pOutput.WriteLine(key_"="_pInput.Attributes(key))
			set key=$order(pInput.Attributes(key))
		}

		do pOutput.WriteLine("-- Content ("_pInput.Size_") --")
		do pInput.Rewind()
		while ( 'pInput.AtEnd ) {
			do pOutput.WriteLine( pInput.ReadLine() )
		}
		do pOutput.Flush()
	} catch error {
		do error.OutputToDevice()
	}
	quit $$$OK
}

} 

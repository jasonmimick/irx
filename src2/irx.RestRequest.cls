/// Ensmeble request message wrapper
/// for a REST service request
class irx.RestRequest extends Ens.Request
{
/// The raw json content of the request
Property Content As %String(MAXLEN = "");

/// The source sending system
Property Source As %String(MAXLEN = "");

/// Unique Id sent back to sender for reference.
Property ControlId As %String; 

Property Timestamp as %String;
}

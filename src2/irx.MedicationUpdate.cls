class irx.MedicationUpdate extends Ens.Request
{
Property study as %String;
Property user as %String;
Property medication as %String;
Property schedule as %String;
Property dosage as %String;

/// This holds the 'status' or flavor of this update
/// e.g. new, cancel, replacement, etc...
Property mood as %String;
}

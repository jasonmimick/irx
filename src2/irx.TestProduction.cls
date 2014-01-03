Class irx.TestProduction Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="irx.TestProduction" LogGeneralTraceEvents="false">
  <Description>Test production to accept REST messages from iRx and save to ActionQ</Description>
  <ActorPoolSize>2</ActorPoolSize>
  <Item Name="irx.InboundRESTService" Category="" ClassName="irx.InboundRESTService" PoolSize="1" Enabled="true" Foreground="false" Comment="" LogTraceEvents="false" Schedule="">
    <Setting Target="Adapter" Name="Port">57775</Setting>
  </Item>
</Production>
}

}


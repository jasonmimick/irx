Class irx.TestProduction Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="irx.TestProduction" TestingEnabled="true" LogGeneralTraceEvents="true">
  <Description>Test production to accept REST messages from iRx and save to ActionQ</Description>
  <ActorPoolSize>2</ActorPoolSize>
  <Item Name="irx.InboundRESTService" Category="" ClassName="irx.InboundRESTService" PoolSize="1" Enabled="true" Foreground="false" Comment="" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="Port">57775</Setting>
    <Setting Target="Host" Name="TargetConfigName">irx.ActionQOperation</Setting>
    <Setting Target="Host" Name="TargetConfigNames">irx.ActionQOperation</Setting>
  </Item>
  <Item Name="irx.ActionQOperation" Category="" ClassName="irx.ActionQOperation" PoolSize="1" Enabled="true" Foreground="false" Comment="" LogTraceEvents="true" Schedule="">
  </Item>
</Production>
}

}


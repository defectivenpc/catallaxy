{ lib, floe }:

let
  T = floe.T;
in
{
  MANAGED_RESOURCE_CONTROL_PLANE = floe.mkSig {
    name = "MANAGED_RESOURCE_CONTROL_PLANE";
    canonicalName = "controlPlane";
    description = "A control plane that installs providers and reconciles the resources they define.";
    fields = {
      namespace = T.k8sName;

      providerKind = T.str;
    };
  };

  MANAGED_RESOURCE_PROVIDER = floe.mkSig {
    name = "MANAGED_RESOURCE_PROVIDER";
    canonicalName = "resourceProvider";
    description = "A provider is healthy and the resource kinds it defines can be applied.";
    fields = {
      crdKinds = (T.listOf T.str);

      healthy = T.str;
    };
  };
}

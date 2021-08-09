local k = import 'ksonnet-util/kausal.libsonnet';

function(provider='gke') {
  local storage = k.storage.v1.storageClass,

  providers:: {
    aks: {
      base:
        storage.withProvisioner('kubernetes.io/azure-disk')
        + storage.withAllowVolumeExpansion(true),
      fast:
        self.base
        + storage.withParameters({ kind: 'Managed', storageaccounttype: 'Premium_LRS' }),
      slow:
        self.base
        + storage.withParameters({ kind: 'Managed', storageaccounttype: 'Standard_LRS' }),
    },
    aws: {
      base:
        storage.withProvisioner('kubernetes.io/aws-ebs')
        + storage.withAllowVolumeExpansion(true),
      fast:
        self.base
        + storage.withParameters({ type: 'io1' }),
      slow:
        self.base
        + storage.withParameters({ type: 'gp2' }),
    },
    digitalocean: {
      base: storage.withProvisioner('dobs.csi.digitalocean.com'),
      fast: self.base,
      slow: self.base,
    },
    gke: {
      base:
        storage.withProvisioner('kubernetes.io/gce-pd')
        + storage.withAllowVolumeExpansion(true),
      fast:
        self.base
        + storage.withParameters({ type: 'pd-ssd' }),
      slow:
        self.base
        + storage.withParameters({ type: 'pd-standard' }),
    },
    linode: {
      base: storage.withProvisioner('linodebs.csi.linode.com'),
      fast: self.base,
      slow: self.base,
    },
    manual: {
      base:
        storage.withProvisioner('kubernetes.io/host-path')
        + storage.withParameters({ type: 'manual' }),
      fast: self.base,
      slow: self.base,
    },
  },

  local p =
    if provider in self.providers
    then self.providers[provider]
    else self.providers.manual,

  storageclass_fast:
    storage.new('fast')
    + storage.withReclaimPolicy('Retain')
    + p.fast,

  storageclass_fast_delete:
    storage.new('fast-dont-retain')
    + storage.withReclaimPolicy('Delete')
    + p.fast,

  storageclass_slow:
    storage.new('slow')
    + storage.withReclaimPolicy('Retain')
    + p.slow,

  storageclass_slow_delete:
    storage.new('slow-dont-retain')
    + storage.withReclaimPolicy('Delete')
    + p.slow,
}

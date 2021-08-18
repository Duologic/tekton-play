local k = import 'k.libsonnet';
local tekton = import 'tekton/main.libsonnet';

{
  local this = self,
  tanka_image:: 'grafana/tanka:0.17.3',

  jsonnet_bundler:
    tekton.core.v1beta1.task.new('jsonnet-bundler', [
      k.core.v1.container.new('jsonnet-bundler', '$(params.image)')
      + k.core.v1.container.withCommand('jb')
      + k.core.v1.container.withArgs(['$(params.args)'])
      + k.core.v1.container.withWorkingDir('$(workspaces.jb_root.path)'),
    ])
    + tekton.core.v1beta1.task.withParams([
      {
        name: 'image',
        type: 'string',
        description: 'Docker image used for the task.',
        default: this.tanka_image,
      },
      {
        name: 'args',
        type: 'array',
        description: 'jb CLI args',
        default: ['install'],
      },
    ])
    + tekton.core.v1beta1.task.withWorkspaces([{
      name: 'jb_root',
      optional: true,
      description: 'Directory containing a `jsonnetfile.json`.',
    }]),

  tanka_cli:
    tekton.core.v1beta1.task.new('tk', [
      k.core.v1.container.new('tanka', '$(params.image)')
      + k.core.v1.container.withArgs(['$(params.args)'])
      + k.core.v1.container.withWorkingDir('$(workspaces.tk_root.path)'),
    ])
    + tekton.core.v1beta1.task.withParams([
      {
        name: 'image',
        type: 'string',
        description: 'Docker image used for the task.',
        default: this.tanka_image,
      },
      {
        name: 'args',
        type: 'array',
        description: 'tk CLI args',
        default: ['--version'],
      },
    ])
    + tekton.core.v1beta1.task.withWorkspaces([{
      name: 'tk_root',
      optional: true,
      description: 'Tanka project root.',
    }]),

  tanka_export:
    tekton.core.v1beta1.task.new('tk-export', [
      k.core.v1.container.new('tanka', '$(params.image)')
      + k.core.v1.container.withArgs([
        'export',
        '$(workspaces.output.path)',
        'environments/',
        '--parallel=$(params.parallel)',
        '--format=$(params.format)',
        '--recursive',
        '--merge',
      ])
      + k.core.v1.container.withWorkingDir('$(workspaces.tk_root.path)'),
    ])
    + tekton.core.v1beta1.task.withParams([
      {
        name: 'image',
        type: 'string',
        description: 'Docker image used for the task.',
        default: this.tanka_image,
      },
      {
        name: 'parallel',
        type: 'string',
        description: 'Number of environments to process in parallel.',
        default: '8',
      },
      {
        name: 'format',
        type: 'string',
        description: 'Filename export format.',
        default: '{{ if .metadata.namespace }}{{.metadata.namespace}}/{{ else }}_cluster/{{ end }}{{.kind}}-{{.metadata.name}}',
      },
    ])
    + tekton.core.v1beta1.task.withWorkspaces([
      {
        name: 'tk_root',
        description: 'Tanka project root.',
      },
      {
        name: 'output',
        description: 'Export output directory.',
      },
    ]),

  sleep:
    tekton.core.v1beta1.task.new('sleep', [
      k.core.v1.container.new('sleep', 'alpine:3.14')
      + k.core.v1.container.withCommand('sleep')
      + k.core.v1.container.withArgs(['$(params.TIME_SECONDS)']),
    ])
    + tekton.core.v1beta1.task.withDescription(
      'Task that sleeps for TIME_SECONDS to inspect the workspace.'
    )
    + tekton.core.v1beta1.task.withParams([{
      name: 'TIME_SECONDS',
      type: 'array',
      description: 'sleep for a while',
      default: ['600'],
    }])
    + tekton.core.v1beta1.task.withWorkspaces([{
      name: 'ws',
      optional: true,
      description: 'Gain access to a workspace.',
    }]),

}

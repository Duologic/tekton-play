local k = import 'k.libsonnet';
local tekton = import 'tekton/main.libsonnet';

{
  sleep:
    tekton.core.v1beta1.task.new('sleep', [
      k.core.v1.container.new('sleep', '$(params.image)')
      + k.core.v1.container.withCommand('sleep')
      + k.core.v1.container.withArgs(['$(params.time_seconds)']),
    ])
    + tekton.core.v1beta1.task.withDescription(
      'Task that sleeps for TIME_SECONDS to inspect the workspace.'
    )
    + tekton.core.v1beta1.task.withParams([
      {
        name: 'image',
        type: 'string',
        description: 'Docker image used for the task.',
        default: 'alpine:3.14',
      },
      {
        name: 'time_seconds',
        type: 'array',
        description: 'Sleep period in seconds.',
        default: ['600'],
      },
    ])
    + tekton.core.v1beta1.task.withWorkspaces([{
      name: 'ws',
      optional: true,
      description: 'Gain access to a workspace.',
    }]),
}

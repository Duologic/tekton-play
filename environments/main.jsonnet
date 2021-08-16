local kubeconfig = import 'kubeconfig.libsonnet';
local server = kubeconfig[0].clusters[0].cluster.server;

local tekton = import 'tekton/main.libsonnet';
local storageclasses = import 'storageclass/classes.libsonnet';

local k = import 'k.libsonnet';
local tk = import 'tanka-util/main.libsonnet';

{
  tekton:
    tk.environment.new('tekton', 'tekton-pipelines', server)
    + tk.environment.withData({
      tekton: tekton.installation {
        config_map_config_artifact_pvc+: {
          data: {
            size: '10Gi',
            storageClassName: 'fast-dont-retain',
          },
        },
      },
    }),

  default:
    tk.environment.new('default', 'default', server)
    + tk.environment.withData({
      storageclasses: storageclasses('gke'),
      ns: [
        k.core.v1.namespace.new('tekton-tutorial'),
      ],

      tanka_pipeline:
        tekton.core.v1beta1.pipeline.new('tanka-pipeline')
        + tekton.core.v1beta1.pipeline.withWorkspace('ws')
        + tekton.core.v1beta1.pipeline.addTask(
          'git-clone',
          'git-clone',
          workspaces=[{ name: 'output', workspace: 'ws' }],
          params=[
            {
              name: 'url',
              value: 'https://github.com/Duologic/tekton-play.git',
            },
          ]
        )
        + tekton.core.v1beta1.pipeline.addTask(
          'jb-install',
          'jb-install',
          workspaces=[{ name: 'jb_root', workspace: 'ws' }],
          runAfter=['git-clone'],
        )
        + tekton.core.v1beta1.pipeline.addTask(
          'tanka',
          'tk',
          params=[{
            name: 'ARGS',
            value: [
              'export',
              'output/',
              'environments/',
              '--recursive',
              '--merge',
              '--parallel=8',
              "--format='{{ if .metadata.namespace }}{{.metadata.namespace}}/{{ else }}_cluster/{{ end }}{{.kind}}-{{.metadata.name}}'",
            ],
          }],
          workspaces=[{ name: 'tk_root', workspace: 'ws' }],
          runAfter=['jb-install'],
        )
        + tekton.core.v1beta1.pipeline.addTask(
          'shell',
          'sleep',
          workspaces=[{ name: 'ws', workspace: 'ws' }],
        ),

      git_clone_task: tekton.tasks.task_git_clone,

      sleep_task:
        tekton.core.v1beta1.task.new('sleep', [
          k.core.v1.container.new('sleep', 'alpine:3.14')
          + k.core.v1.container.withCommand('sleep')
          + k.core.v1.container.withArgs(['$(params.TIME_SECONDS)']),
        ])
        + tekton.core.v1beta1.task.withDescription(
          'Task that sleeps for a while to inspect the pipeline/workspace.'
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

      jb_install_task:
        tekton.core.v1beta1.task.new('jb-install', [
          k.core.v1.container.new('jb-install', 'grafana/tanka:0.17.2')
          + k.core.v1.container.withCommand('jb')
          + k.core.v1.container.withArgs(['install'])
          + k.core.v1.container.withWorkingDir('$(workspaces.jb_root.path)'),
        ])
        + tekton.core.v1beta1.task.withWorkspaces([{
          name: 'jb_root',
          optional: true,
          description: 'Include workspace with Jsonnet files.',
        }]),

      tanka_task:
        tekton.core.v1beta1.task.new('tk', [
          k.core.v1.container.new('tanka', 'grafana/tanka:0.17.2')
          + k.core.v1.container.withArgs(['$(params.ARGS)'])
          + k.core.v1.container.withWorkingDir('$(workspaces.tk_root.path)'),
        ])
        + tekton.core.v1beta1.task.withParams([{
          name: 'ARGS',
          type: 'array',
          description: 'tk CLI args',
          default: ['--version'],
        }])
        + tekton.core.v1beta1.task.withWorkspaces([{
          name: 'tk_root',
          optional: true,
          description: 'Include workspace with Jsonnet files.',
        }]),

    }),

  tutorial:
    tk.environment.new('tutorial', 'tekton-tutorial', server)
    + tk.environment.withData({
      local ws_name = 'hello',
      write_task:
        tekton.core.v1beta1.task.new('write-hello', [
          k.core.v1.container.new('write-hello', 'ubuntu')
          + k.core.v1.container.withCommand('bash')
          + k.core.v1.container.withArgs([
            '-c',
            'echo Hello World! > /workspace/' + ws_name + '/world && ls -laht /workspace/hello',
          ]),
        ])
        + tekton.core.v1beta1.task.withWorkspace(ws_name),

      read_task:
        tekton.core.v1beta1.task.new('read-hello', [
          k.core.v1.container.new('read-hello', 'ubuntu')
          + k.core.v1.container.withCommand('cat')
          + k.core.v1.container.withArgs('/workspace/' + ws_name + '/world'),
        ])
        + tekton.core.v1beta1.task.withWorkspace(ws_name),

      sleep_task:
        tekton.core.v1beta1.task.new('sleep-helloparams.ARGS', [
          k.core.v1.container.new('sleep-hello', 'ubuntu')
          + k.core.v1.container.withCommand('sleep')
          + k.core.v1.container.withArgs('300'),
        ])
        + tekton.core.v1beta1.task.withWorkspace(ws_name),

      write_pod_name_task:
        tekton.core.v1beta1.task.new('write-pod-name-hello', [
          k.core.v1.container.new('write-pod-name-hello-container', 'ubuntu')
          + k.core.v1.container.withEnv([
            k.core.v1.envVar.fromFieldPath('POD_NAME', 'metadata.name'),
          ])
          + k.core.v1.container.withCommand('echo')
          + k.core.v1.container.withArgs([
            'Hello $(POD_NAME)!',
          ]),
        ]),

      pipeline:
        tekton.core.v1beta1.pipeline.new('hello-pod-name-pipeline')
        + tekton.core.v1beta1.pipeline.withWorkspace(ws_name)
        + tekton.core.v1beta1.pipeline.withTask(self.write_pod_name_task)
        + tekton.core.v1beta1.pipeline.withTask(self.sleep_task)
        + tekton.core.v1beta1.pipeline.withTask(self.write_task)
        + tekton.core.v1beta1.pipeline.withTask(self.read_task, self.write_task),

      pipelineRun::
        tekton.core.v1beta1.pipelineRun.new(self.pipeline)
        + tekton.core.v1beta1.pipelineRun.withWorkspaceStorage(
          storageClass='fast-dont-retain',
          size='1Gi',
        ),

      triggerTemplate:
        tekton.triggers.v1beta1.triggerTemplate.new('hello-pod-name-trigger', self.pipelineRun),

      trigger:
        tekton.triggers.v1beta1.trigger.new('trigger-1', self.triggerTemplate),
    }),
}

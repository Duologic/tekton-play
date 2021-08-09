local kubeconfig = import 'kubeconfig.libsonnet';
local server = kubeconfig[0].clusters[0].cluster.server;

local tekton = import 'tekton/main.libsonnet';
local storageclasses = import 'storageclass/classes.libsonnet';

local k = import 'k.libsonnet';
local tk = import 'tanka-util/main.libsonnet';

local tt = {
  v1beta1: {
    task: {
      new(name, steps): {
        apiVersion: 'tekton.dev/v1beta1',
        kind: 'Task',
        metadata: { name: name },
        spec: { steps: steps },
      },
      withWorkspace(name): {
        spec+: {
          workspaces+: [{ name: name }],
        },
      },
    },
    pipeline: {
      new(name, tasks=[]): {
        apiVersion: 'tekton.dev/v1beta1',
        kind: 'Pipeline',
        metadata: { name: name },
        spec: { tasks: tasks },
      },
      withWorkspace(name): {
        spec+: {
          workspaces+: [{
            name: name,
          }],
          tasks: [
            task { workspaces: [{ name: name, workspace: name }] }
            for task in super.tasks
          ],
        },
      },
      withTask(task, runAfterTask={}): {
        spec+: {
          tasks+: [
            {
              name: task.metadata.name,
              taskRef: { name: task.metadata.name },
              [if runAfterTask != {} then 'runAfter']: [
                runAfterTask.metadata.name,
              ],
            },
          ],
        },
      },
    },
    pipelineRun: {
      new(pipeline): {
        apiVersion: 'tekton.dev/v1beta1',
        kind: 'PipelineRun',
        pipeline:: pipeline,
        metadata: { name: pipeline.metadata.name + '-2' },
        spec: { pipelineRef: { name: pipeline.metadata.name } },
      },
      withWorkspaceStorage(size='1Gi'): {
        local pipeline = self.pipeline,
        spec+: {
          workspaces: [
            {
              name: workspace.name,
              local pvcTemplate = k.core.v1.persistentVolumeClaimTemplate,
              volumeClaimTemplate:
                pvcTemplate.spec.withStorageClassName('fast-dont-retain')
                + pvcTemplate.spec.resources.withRequests({ storage: size })
                + pvcTemplate.spec.withAccessModes('ReadWriteOnce'),
            }
            for workspace in pipeline.spec.workspaces
          ],
        },
      },
    },
  },
};


{
  tekton:
    tk.environment.new('tekton', 'tekton-pipelines', server)
    + tk.environment.withData(
      tekton {
        config_map_config_artifact_pvc+: {
          data: {
            size: '10Gi',
            storageClassName: 'fast-dont-retain',
          },
        },
      }
    ),

  default:
    tk.environment.new('default', 'default', server)
    + tk.environment.withData({
      storageclasses: storageclasses('gke'),
      ns: [
        k.core.v1.namespace.new('tekton-tutorial'),
      ],
    }),

  tutorial:
    tk.environment.new('tutorial', 'tekton-tutorial', server)
    + tk.environment.withData({
      local workspace = '/workspace/hello',
      write_task:
        tt.v1beta1.task.new('write-hello', [
          k.core.v1.container.new('write-hello', 'ubuntu')
          + k.core.v1.container.withCommand('echo')
          + k.core.v1.container.withArgs([
            'Hello World! > ' + workspace + '/hello',
          ]),
        ])
        + tt.v1beta1.task.withWorkspace('hello'),

      read_task:
        tt.v1beta1.task.new('read-hello', [
          k.core.v1.container.new('read-hello', 'ubuntu')
          + k.core.v1.container.withCommand('cat')
          + k.core.v1.container.withArgs(workspace + '/hello'),
        ])
        + tt.v1beta1.task.withWorkspace('hello'),

      pipeline:
        tt.v1beta1.pipeline.new('hello')
        + tt.v1beta1.pipeline.withTask(self.write_task)
        //+ tt.v1beta1.pipeline.withTask(self.read_task, self.write_task)
        + tt.v1beta1.pipeline.withWorkspace('hello'),

      pipelineRun:
        tt.v1beta1.pipelineRun.new(self.pipeline)
        + tt.v1beta1.pipelineRun.withWorkspaceStorage(),
    }),
}

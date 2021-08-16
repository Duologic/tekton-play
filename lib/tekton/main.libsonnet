local tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local kustomize = tanka.kustomize.new(std.thisFile);
local k = import 'k.libsonnet';

{
  installation:
    kustomize.build('./installation'),

  tasks:
    kustomize.build('./tasks'),

  core: {
    v1beta1: {
      task: {
        new(name, steps): {
          apiVersion: 'tekton.dev/v1beta1',
          kind: 'Task',
          metadata: { name: name },
          spec: { steps: steps },
        },
        withDescription(description): {
          spec+: { description: description },
        },
        withParams(params): {
          spec+: { params: if std.isArray(params) then params else [params] },
        },
        withParamsMixin(params): {
          spec+: { params+: if std.isArray(params) then params else [params] },
        },
        withWorkspace(name): {
          spec+: { workspaces: [{ name: name }] },
        },
        withWorkspaceMixin(name): {
          spec+: { workspaces+: [{ name: name }] },
        },
        withWorkspaces(workspaces): {
          spec+: {
            workspaces: if std.isArray(workspaces) then workspaces else [workspaces],
          },
        },
        withWorkspacesMixin(workspaces): {
          spec+: {
            workspaces+: if std.isArray(workspaces) then workspaces else [workspaces],
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
          },
        },
        addTask(
          name,
          taskRef,
          params=[],
          workspaces=[],
          runAfter=[]
        ): {
          spec+: {
            local spec = self,
            tasks+: [
              {
                name: name,
                taskRef: { name: taskRef },
                params: params,
                workspaces: workspaces,
                runAfter: runAfter,
              },
            ],
          },
        },
        withTask(task, runAfterTask={}): {
          spec+: {
            local spec = self,
            tasks+: [
              {
                name: task.metadata.name,
                taskRef: { name: task.metadata.name },

                // Declare dependencies
                [if runAfterTask != {} then 'runAfter']: [
                  runAfterTask.metadata.name,
                ],

                local task_workspaces =
                  if 'workspaces' in task.spec
                  then task.spec.workspaces
                  else [],

                // Match pipeline workspace to task workspace on name
                [if 'workspaces' in spec then 'workspaces']: [
                  { name: workspace.name, workspace: workspace.name }
                  for task_ws in task_workspaces
                  for workspace in spec.workspaces
                  if task_ws.name == workspace.name
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
          metadata: { generateName: pipeline.metadata.name + '-' },
          spec: { pipelineRef: { name: pipeline.metadata.name } },
        },
        withWorkspaceStorage(storageClass='default', size='1Gi'): {
          local pipeline = self.pipeline,
          spec+: {
            workspaces: [
              {
                name: workspace.name,

                local pvcTemplate = k.core.v1.persistentVolumeClaimTemplate,
                volumeClaimTemplate:
                  pvcTemplate.spec.withStorageClassName(storageClass)
                  + pvcTemplate.spec.resources.withRequests({ storage: size })
                  + pvcTemplate.spec.withAccessModes('ReadWriteOnce'),
              }
              for workspace in pipeline.spec.workspaces
            ],
          },
        },
      },
    },
  },

  triggers: {
    v1beta1: {
      triggerTemplate: {
        new(name, pipelineRun): {
          apiVersion: 'triggers.tekton.dev/v1beta1',
          kind: 'TriggerTemplate',
          metadata: { name: name },
          spec: {
            resourceTemplates: [
              pipelineRun,
            ],
          },
        },
      },
      trigger: {
        new(name, template): {
          apiVersion: 'triggers.tekton.dev/v1beta1',
          kind: 'Trigger',
          metadata: { name: name },
          spec: {
            template: {
              ref: template.metadata.name,
            },
          },
        },
      },
    },
  },
}

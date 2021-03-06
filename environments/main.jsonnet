local kubeconfig = import 'kubeconfig.libsonnet';
local server = kubeconfig[0].clusters[0].cluster.server;

local tekton = import 'tekton/main.libsonnet';
local tkn_tasks = import 'tkn-tasks/main.libsonnet';

local storageclasses = import 'storageclass/classes.libsonnet';

local k = import 'k.libsonnet';
local tk = import 'tanka-util/main.libsonnet';

{
  tekton:
    tk.environment.new('tekton', 'tekton-pipelines', server)
    + tk.environment.withInjectLabels()
    + tk.environment.withData({
      tekton: tekton.installation {
        // namespace will get created by cluster-resources
        namespace_tekton_pipelines+:: {},

        // allow running tasks in the same pipeline but on different nodes
        config_map_feature_flags+: {
          data+: {
            'disable-affinity-assistant': 'true',
          },
        },

        // beef-up the controller for better performance
        deployment_tekton_pipelines_controller+:
          k.apps.v1.deployment.mapContainersWithName(
            ['tekton-pipelines-controller'],
            function(c)
              c
              + k.core.v1.container.withArgsMixin([
                '-kube-api-qps=50',
                '-kube-api-burst=50',
                '-threads-per-controller=15',
              ])
              + k.core.v1.container.resources.withRequestsMixin({
                cpu: 15,
              })
          ),

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
    + tk.environment.withInjectLabels()
    + tk.environment.withData({
      storageclasses: storageclasses('gke'),
      ns: [
        k.core.v1.namespace.new('tekton-pipelines'),
      ],
    }),

  pipelines:
    tk.environment.new('pipelines', 'default', server)
    + tk.environment.withInjectLabels()
    + tk.environment.withData({
      local pipeline = tekton.core.v1beta1.pipeline,
      local workspace = 'ws',
      tanka_pipeline:
        pipeline.new('tanka-pipeline')
        + pipeline.withWorkspace(workspace)
        + pipeline.addTask(
          'git-clone',
          'git-clone',
          workspaces=[{
            name: 'output',
            workspace: workspace,
            subpath: 'input',
          }],
          params=[{
            name: 'url',
            value: 'https://github.com/Duologic/tekton-play.git',
          }]
        )
        + pipeline.addTask(
          'jb-install',
          self.tasks.jb_install.metadata.name,
          workspaces=[{
            name: 'jb_root',
            workspace: workspace,
            subpath: 'input',
          }],
          runAfter=['git-clone'],
        )
        + pipeline.addTask(
          'tanka-export',
          self.tasks.tanka_export.metadata.name,
          runAfter=['jb-install'],
          workspaces=[{
            name: 'tk_root',
            workspace: workspace,
            subpath: 'input',
          }, {
            name: 'output',
            workspace: workspace,
            subpath: 'output',
          }],
        )
        + pipeline.addTask(
          'kubeval',
          self.tasks.kubeval.metadata.name,
          runAfter=['tanka-export'],
          workspaces=[{
            name: 'source',
            workspace: workspace,
            subpath: 'output',
          }],
          params=[{
            name: 'args',
            value: [
              '--force-color',
              '--ignore-missing-schemas',
              '--strict',
            ],
          }],
        ),

      tasks: {
        git_clone: tekton.tasks.task_git_clone,
        kubeval: tekton.tasks.task_kubeval,
        jb_install: tkn_tasks.tanka.jsonnet_bundler,
        tanka_export: tkn_tasks.tanka.export,
      },
    }),
}

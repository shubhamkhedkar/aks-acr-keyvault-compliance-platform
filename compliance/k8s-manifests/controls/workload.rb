require 'yaml'

docs = YAML.load_stream(File.read(input('manifest_file'))).compact
by_kind = docs.group_by { |d| d['kind'] }
deployment = by_kind.fetch('Deployment', []).find { |d| d.dig('metadata', 'name') == 'flagpost' } || {}
pod = deployment.dig('spec', 'template', 'spec') || {}
container = (pod['containers'] || []).first || {}

control 'k8s-01-restricted-namespace' do
  impact 1.0
  title 'Namespace enforces the restricted Pod Security Standard'
  desc 'Admission rejects privileged, host-namespace or root pods in the flagpost namespace.'
  ns = by_kind.fetch('Namespace', []).first || {}
  describe ns.dig('metadata', 'labels') do
    its(['pod-security.kubernetes.io/enforce']) { should cmp 'restricted' }
  end
end

control 'k8s-02-container-hardening' do
  impact 1.0
  title 'Container runs non-root, read-only, with no capabilities and RuntimeDefault seccomp'
  desc 'Mirrors the AKS Azure Policy restricted initiative so violations fail before reaching the cluster.'
  describe pod.dig('securityContext') do
    its(['runAsNonRoot']) { should cmp true }
    its(%w[seccompProfile type]) { should cmp 'RuntimeDefault' }
  end
  describe container.dig('securityContext') do
    its(['allowPrivilegeEscalation']) { should cmp false }
    its(['readOnlyRootFilesystem']) { should cmp true }
    its(%w[capabilities drop]) { should include 'ALL' }
  end
  describe pod do
    its(['hostNetwork']) { should be_nil }
    its(['hostPID']) { should be_nil }
    its(['automountServiceAccountToken']) { should cmp false }
  end
end

control 'k8s-03-resources-and-probes' do
  impact 0.7
  title 'Requests, limits and all three probes are defined'
  desc 'Needed for scheduling, HPA decisions and safe rolling updates.'
  describe container do
    its(%w[resources requests cpu]) { should_not be_nil }
    its(%w[resources limits memory]) { should_not be_nil }
    its(['startupProbe']) { should_not be_nil }
    its(['livenessProbe']) { should_not be_nil }
    its(%w[readinessProbe httpGet path]) { should cmp '/readyz' }
  end
end

control 'k8s-04-image-provenance' do
  impact 1.0
  title 'Image comes from the platform ACR and is pinned by digest'
  desc 'The pipeline rewrites the image to <acr>.azurecr.io/flagpost@sha256:<digest> before deploying.'
  only_if('production render') { input('expect_csi') }
  describe container['image'] do
    it { should match(/\A[a-z0-9]+\.azurecr\.io\/flagpost@sha256:[0-9a-f]{64}\z/) }
  end
end

control 'k8s-05-workload-identity-and-csi' do
  impact 1.0
  title 'Secrets come from Key Vault via the CSI driver using Workload Identity'
  desc 'No Kubernetes Secret objects carry application credentials in production.'
  only_if('production render') { input('expect_csi') }
  labels = deployment.dig('spec', 'template', 'metadata', 'labels') || {}
  describe labels do
    its(['azure.workload.identity/use']) { should cmp 'true' }
  end
  csi = (pod['volumes'] || []).find { |v| v['csi'] }
  describe csi.to_h.dig('csi', 'driver') do
    it { should cmp 'secrets-store.csi.k8s.io' }
  end
  spc = by_kind.fetch('SecretProviderClass', []).first || {}
  describe spc.dig('spec', 'parameters') do
    its(['usePodIdentity']) { should cmp 'false' }
    its(['clientID']) { should match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/) }
  end
  describe by_kind.fetch('Secret', []) do
    it { should be_empty }
  end
  sa = by_kind.fetch('ServiceAccount', []).first || {}
  describe sa.dig('metadata', 'annotations') do
    its(['azure.workload.identity/client-id']) { should_not be_nil }
  end
end

control 'k8s-06-availability-and-network' do
  impact 0.7
  title 'PDB, HPA, zone spread and default-deny NetworkPolicy are present'
  desc 'Keeps the service up through node upgrades and limits lateral movement.'
  describe by_kind.fetch('PodDisruptionBudget', []).length do
    it { should cmp 1 }
  end
  describe by_kind.fetch('HorizontalPodAutoscaler', []).first.to_h.dig('spec', 'minReplicas') do
    it { should be >= 2 }
  end
  keys = (pod['topologySpreadConstraints'] || []).map { |c| c['topologyKey'] }
  describe keys do
    it { should include 'topology.kubernetes.io/zone' }
  end
  deny = by_kind.fetch('NetworkPolicy', []).find { |n| n.dig('spec', 'podSelector') == {} }
  describe deny.to_h.dig('spec', 'policyTypes') do
    it { should include 'Ingress' }
    it { should include 'Egress' }
  end
end

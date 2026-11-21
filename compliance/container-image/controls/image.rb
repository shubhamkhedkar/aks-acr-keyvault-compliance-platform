control 'img-01-non-root' do
  impact 1.0
  title 'PID 1 runs as the unprivileged flagpost user (10001)'
  desc 'Matches runAsUser in the Deployment and the restricted Pod Security Standard.'
  describe file('/proc/1/status') do
    its('content') { should match(/^Uid:\s+10001\s/) }
    its('content') { should match(/^Gid:\s+10001\s/) }
  end
  describe passwd.uids(10_001) do
    its('users') { should cmp ['flagpost'] }
  end
  describe passwd.users('flagpost') do
    its('shells') { should cmp ['/usr/sbin/nologin'] }
  end
end

control 'img-02-no-package-tooling' do
  impact 0.7
  title 'pip, ensurepip and apt package lists are removed from the runtime image'
  desc 'Nothing can be installed into a running container.'
  %w[/usr/local/bin/pip /usr/local/bin/pip3 /opt/venv/bin/pip].each do |path|
    describe file(path) do
      it { should_not exist }
    end
  end
  %w[/usr/local/lib/python3.13/ensurepip /usr/local/lib/python3.13/site-packages/pip].each do |dir|
    describe file(dir) do
      it { should_not exist }
    end
  end
  describe command('apt-get --version') do
    its('exit_status') { should eq 0 } # dpkg stays (base image), but its lists are emptied
  end
  describe command('ls /var/lib/apt/lists | grep -v -E "^(partial|lock)$" | wc -l') do
    its('stdout.strip') { should cmp '0' }
  end
end

control 'img-03-code-is-immutable' do
  impact 0.7
  title 'Application code and seed data are root-owned and not writable by the app user'
  desc 'Even without readOnlyRootFilesystem the app user cannot modify its own code.'
  %w[/opt/app/flagpost/app.py /etc/flagpost/flags.json].each do |path|
    describe file(path) do
      it { should exist }
      its('owner') { should cmp 'root' }
      it { should_not be_writable.by('others') }
      it { should_not be_writable.by_user('flagpost') }
    end
  end
end

control 'img-04-no-setuid' do
  impact 0.5
  title 'Image has no setuid/setgid binaries outside the base allow-list'
  desc 'allowPrivilegeEscalation=false blocks them at runtime; this keeps the image itself lean.'
  allowed = %w[/usr/bin/chfn /usr/bin/chsh /usr/bin/gpasswd /usr/bin/mount /usr/bin/newgrp /usr/bin/passwd
               /usr/bin/su /usr/bin/umount /usr/bin/chage /usr/bin/expiry /usr/sbin/unix_chkpwd]
  found = command('find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null').stdout.split("\n")
  describe found - allowed do
    it { should be_empty }
  end
end

control 'img-05-serves-health' do
  impact 1.0
  title 'The service answers /healthz inside the container'
  desc 'Same check the Docker HEALTHCHECK and the Kubernetes liveness probe use.'
  probe = "python -c \"import urllib.request;print(urllib.request.urlopen('http://127.0.0.1:8080/healthz',timeout=3).read().decode())\""
  describe command(probe) do
    its('exit_status') { should eq 0 }
    its('stdout') { should match(/"status":"ok"/) }
  end
end

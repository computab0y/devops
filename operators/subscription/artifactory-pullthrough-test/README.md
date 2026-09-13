# artifactory-pullthrough-test

A throwaway proof that images can be pulled through Artifactory's `docker`
virtual repo (which aggregates `docker-local` + `docker-remote`, the latter
proxying DockerHub with the credentials set in
[`docs/artifactory-dockerhub-sync-guide.md`](../../../../docs/artifactory-dockerhub-sync-guide.md)).

Deploys two stock DockerHub images (`nginx:alpine`, `httpd:alpine`) pulled via:

```
artifactory-artifactory.apps.okd.funky-bash.com/docker/library/<image>:<tag>
```

## Apply

```bash
oc apply -k operators/subscription/artifactory-pullthrough-test/base
```

This creates the namespace, the `default-anyuid` RoleBinding (see note below),
and the two Deployment/Service/Route sets. It does **not** create the image
pull secret — that holds real Artifactory credentials and is deliberately
kept out of git.

## Create the pull secret (one-time, not in git)

```bash
oc create secret docker-registry artifactory-pull-secret \
  -n artifactory-pullthrough-test \
  --docker-server=artifactory-artifactory.apps.okd.funky-bash.com \
  --docker-username=<your-artifactory-username> \
  --docker-password=<your-artifactory-password-or-identity-token>

oc secrets link default artifactory-pull-secret --for=pull -n artifactory-pullthrough-test
```

(Or via the console: Secrets → Create → Image pull secret, then it's already
referenced by both Deployments' `imagePullSecrets`.)

## Why the anyuid RoleBinding

Stock DockerHub `nginx`/`httpd` images aren't built to OpenShift's "arbitrary
UID" convention:
- `nginx` crashes with `mkdir() "/var/cache/nginx/client_temp" failed (13:
  Permission denied)` under the default `restricted` SCC.
- `httpd` crashes with `Permission denied: could not bind to address
  0.0.0.0:80` — non-root can't bind ports < 1024.

`rbac.yaml` grants just this namespace's `default` ServiceAccount the
`anyuid` SCC so both images can run as their default root user. This is a
scoped, deliberate trade-off for a disposable test namespace, applied with
explicit sign-off — not a default to reuse elsewhere without thinking about
it. The alternative (no anyuid) is OpenShift-friendly images (e.g.
`registry.access.redhat.com/ubi9/nginx-124`) or emptyDir volumes over the
specific paths each image needs to write.

## Verify

```bash
oc get pods -n artifactory-pullthrough-test
oc get route -n artifactory-pullthrough-test
```

Both routes should return their default landing pages ("Welcome to nginx!"
/ "It works!"). Confirmed working 2026-09-13. You can also check Artifactory
itself — `docker-remote-cache/library/nginx` and `.../library/httpd` will
show up once pulled, proving the images actually flowed through Artifactory
rather than being pulled directly from DockerHub.

## Tear down

```bash
oc delete -k operators/subscription/artifactory-pullthrough-test/base
oc delete secret artifactory-pull-secret -n artifactory-pullthrough-test
oc delete project artifactory-pullthrough-test
```

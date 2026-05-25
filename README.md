# 🚀 GitHub Action for GitOps

This GitHub Action can be used for our GitOps workflow. The GitHub Action will build and push the Docker image for your
service and deploys
the new version at your Kubernetes clusters.

## Requirement

When you want to use this GitHub Action your GitHub repository should have a `dev` and `master` / `main` branch and it
should use tags for
releases.

- For the `dev` branch we will change the files specified under `gitops-dev`.
- For the `master` / `main` branch we will change the files specified under `gitops-stage`.
- For a new tag the files under `gitops-prod` will be used.

This GitOps setup should be the default for all your repositories. However, if you have a special case, you can
leave `gitops-dev`, `gitops-stage` and `gitops-prod` undefined, then those steps will be skipped.

## Usages

### Build, Push and Deploy Docker Image

#### Recommended format

Use `gitops-namespace` and `gitops-updates`. The environment (dev/stage/prod) is derived from the git ref automatically — no need to repeat the same files three times.

```yaml
name: CD

on: [ push ]

jobs:
  ci-cd:
    name: Build, Push and Deploy

    runs-on: ubuntu-24.04

    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: GitOps (build, push and deploy a new Docker image)
        uses: Staffbase/gitops-github-action@v7.1
        with:
          docker-username: ${{ vars.HARBOR_USERNAME }}
          docker-password: ${{ secrets.HARBOR_PASSWORD }}
          docker-image: sb-images/my-service
          gitops-token: ${{ secrets.GITOPS_TOKEN }}
          gitops-namespace: my-service
          gitops-updates: |-
            my-service-cr.yaml
```

The action looks up `kubernetes/namespaces/<gitops-namespace>/<env>/` in the GitOps repository and expands each line to a full path for every region directory found there. A service deployed only to `prod/core` will only update that directory; a customer-facing service with `prod/de1`, `prod/us1`, `prod/au1` etc. will update all of them automatically. Adding a new region to the GitOps repo requires no changes in service repos.

The field specifier on each line is optional and resolved as follows:

| Line format | Resolved yq field |
|---|---|
| `my-service-cr.yaml` | `spec.template.spec.containers.<namespace>.image` |
| `my-service-cr.yaml authentication` | `spec.template.spec.containers.authentication.image` |
| `my-service-cr.yaml spec.template.spec.initContainers.migrate.image` | used as-is |

The second form is useful when the container name differs from the namespace (e.g. matrix builds). The third form covers init containers or any other custom yq path.

#### Explicit format (legacy / escape hatch)

Full paths can still be specified directly. Lines starting with `kubernetes/` are passed through unchanged, so existing configurations continue to work without modification. Explicit and shorthand lines can be mixed within the same input.

```yaml
          gitops-prod: |-
            kubernetes/namespaces/my-service/prod/de1/my-service-cr.yaml spec.template.spec.containers.my-service.image
            kubernetes/namespaces/my-service/prod/us1/my-service-cr.yaml spec.template.spec.containers.my-service.image
            kubernetes/namespaces/my-service/prod/au1/my-service-cr.yaml spec.template.spec.containers.my-service.image
```

### Build and Push Docker Image

```yaml
name: CD

on: [ push ]

jobs:
  ci-cd:
    name: Build and Push

    runs-on: ubuntu-24.04

    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: GitOps (build and push a new Docker image)
        uses: Staffbase/gitops-github-action@v7.1
        with:
          docker-username: ${{ vars.HARBOR_USERNAME }}
          docker-password: ${{ secrets.HARBOR_PASSWORD }}
          docker-image: private/diablo-redbook
```

### Deploy Docker Image

```yaml
name: CD

on: [ push ]

jobs:
  ci-cd:
    name: Deploy

    runs-on: ubuntu-24.04

    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: GitOps (deploy a new Docker image)
        uses: Staffbase/gitops-github-action@v7.1
        with:
          docker-image: private/diablo-redbook
          gitops-token: ${{ secrets.GITOPS_TOKEN }}
          gitops-dev: |-
            clusters/customization/dev/mothership/diablo-redbook/diablo-redbook-helm.yaml spec.template.spec.containers.redbook.image
          gitops-stage: |-
            clusters/customization/stage/mothership/diablo-redbook/diablo-redbook-helm.yaml spec.template.spec.containers.redbook.image
          gitops-prod: |-
            clusters/customization/prod/mothership/diablo-redbook/diablo-redbook-helm.yaml spec.template.spec.containers.redbook.image
```

### Deployment tracking annotations

Whenever the action updates a GitOps file, it stamps the following annotations onto the manifest's `metadata.annotations`:

| Annotation | Value |
|------------|-------|
| `deploy.staffbase.com/repositoryFullName` | The source repository in `owner/repo` form (`$GITHUB_REPOSITORY`) |
| `deploy.staffbase.com/commitSha` | The commit SHA being deployed (`$GITHUB_SHA`) |
| `deploy.staffbase.com/version` | The deployed image tag — `dev-<short-sha>` on `dev`, `main-<short-sha>` on `main`/`master`, the tag name on tag pushes |

These keys mirror the [Swarmia Deployment API](https://help.swarmia.com/settings/organization/configuring-deployments-in-swarmia) field names and are read by `flux-deployment-reporter` to report deployments to Swarmia once Flux finishes reconciling.

## Inputs

| Name                        | Description                                                                                                                    | Default                                              |
|-----------------------------|--------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------|
| `docker-registry`           | Docker Registry                                                                                                                | `registry.staffbase.com`                                 |
| `docker-registry-api`       | Docker Registry API (used for retagging without pulling)                                                                       | `https://registry.staffbase.com/v2/` |
| `docker-image`              | Docker Image                                                                                                                   |                                                      |
| `docker-custom-tag`         | Docker Custom Tag to be set on the image                                                                                       |                                                      |
| `docker-username`           | Username for the Docker Registry                                                                                               |                                                      |
| `docker-password`           | Password for the Docker Registry                                                                                               |                                                      |
| `docker-file`               | Dockerfile                                                                                                                     | `./Dockerfile`                                       |
| `docker-build-args`         | List of build-time variables                                                                                                   |                                                      |
| `docker-build-secrets`      | List of secrets to expose to the build (e.g., key=string, GIT_AUTH_TOKEN=mytoken)                                              |                                                      |
| `docker-build-secret-files` | List of secret files to expose to the build (e.g., key=filename, MY_SECRET=./secret.txt)                                       |                                                      |
| `docker-build-target`       | Sets the target stage to build like: "runtime"                                                                                 |                                                      |
| `docker-build-platforms`       | Sets the target platforms for build                                                                                 | linux/amd64 |
| `docker-build-provenance`   | Generate [provenance](https://docs.docker.com/build/attestations/slsa-provenance/) attestation for the build                   | `false`                                              |
| `docker-disable-retagging`  | Disables retagging of existing images and run a new build instead                                                              | `false`                                              |
| `gitops-organization`       | GitHub Organization for GitOps                                                                                                 | `Staffbase`                                          |
| `gitops-repository`         | GitHub Repository for GitOps                                                                                                   | `mops`                                               |
| `gitops-user`               | GitHub User for GitOps                                                                                                         | `Staffbot`                                           |
| `gitops-email`              | GitHub Email for GitOps                                                                                                        | `staffbot@staffbase.com`                             |
| `gitops-token`              | GitHub Token for GitOps                                                                                                        |                                                      |
| `gitops-namespace`          | Kubernetes namespace for region auto-discovery. Required when using `gitops-updates` or shorthand path format (see Usage).     |                                                      |
| `gitops-updates`            | Files to update for all environments. Environment derived from git ref. Replaces `gitops-dev/stage/prod` when set.             |                                                      |
| `gitops-dev`                | Files to update for DEV (legacy). Use `gitops-updates` instead.                                                                |                                                      |
| `gitops-stage`              | Files to update for STAGE (legacy). Use `gitops-updates` instead.                                                              |                                                      |
| `gitops-prod`               | Files to update for PROD (legacy). Use `gitops-updates` instead.                                                               |                                                      |
| `working-directory`         | The directory in which the GitOps action should be executed. The docker-file variable should be relative to working directory. | `.`                                                  |

## Outputs

| Name            | Description         |
|-----------------|---------------------|
| `docker-digest`  | Digest of the image                                                             |
| `docker-tag`     | Tag of the image                                                                |

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct, and the process for submitting pull
requests to us.

## License

This project is licensed under the Apache-2.0 License - see the [LICENSE.md](LICENSE) file for details.

<table>
  <tr>
    <td>
      <img src="docs/assets/images/staffbase.png" alt="Staffbase GmbH" width="96" />
    </td>
    <td>
      <b>Staffbase GmbH</b>
      <br />Staffbase is an internal communications platform built to revolutionize the way you work and unite your company. Staffbase is hiring: <a href="https://jobs.staffbase.com" target="_blank" rel="noreferrer">jobs.staffbase.com</a>
      <br /><a href="https://github.com/Staffbase" target="_blank" rel="noreferrer">GitHub</a> | <a href="https://staffbase.com/" target="_blank" rel="noreferrer">Website</a> | <a href="https://jobs.staffbase.com" target="_blank" rel="noreferrer">Jobs</a>
    </td>
  </tr>
</table>

## Releasing new versions

Go to the release overview page and publish the draft release with a new version number. Make sure to update the
floating version commit.

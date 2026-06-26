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
          docker-image: private/my-service
          gitops-token: ${{ secrets.GITOPS_TOKEN }}
          gitops-dev: |-
            clusters/customization/dev/mothership/my-service/my-service-helm.yaml spec.template.spec.containers.redbook.image
          gitops-stage: |-
            clusters/customization/stage/mothership/my-service/my-service-helm.yaml spec.template.spec.containers.redbook.image
          gitops-prod: |-
            clusters/customization/prod/mothership/my-service/my-service-helm.yaml spec.template.spec.containers.redbook.image
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
          docker-image: private/my-service
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
          docker-image: private/my-service
          gitops-token: ${{ secrets.GITOPS_TOKEN }}
          gitops-dev: |-
            clusters/customization/dev/mothership/my-service/my-service-helm.yaml spec.template.spec.containers.redbook.image
          gitops-stage: |-
            clusters/customization/stage/mothership/my-service/my-service-helm.yaml spec.template.spec.containers.redbook.image
          gitops-prod: |-
            clusters/customization/prod/mothership/my-service/my-service-helm.yaml spec.template.spec.containers.redbook.image
```

### Deployment tracking annotations

Whenever the action updates a GitOps file, it stamps the following annotations onto the manifest's `metadata.annotations`:

| Annotation | Value |
|------------|-------|
| `deploy.staffbase.com/repositoryFullName` | The source repository in `owner/repo` form (`$GITHUB_REPOSITORY`) |
| `deploy.staffbase.com/commitSha` | The commit SHA being deployed (`$GITHUB_SHA`) |
| `deploy.staffbase.com/version` | The deployed image tag — `dev-<timestamp>-<short-sha>` on `dev`, `main-<timestamp>-<short-sha>` on `main`, `master-<timestamp>-<short-sha>` on `master` (the UTC timestamp is inserted by default; with `docker-tag-timestamp: 'false'` it falls back to `<prefix>-<short-sha>`), the version without the leading `v` on `v*` tag pushes, and the tag name on other tag pushes |

These keys mirror the [Swarmia Deployment API](https://help.swarmia.com/settings/organization/configuring-deployments-in-swarmia) field names and are read by `flux-deployment-reporter` to report deployments to Swarmia once Flux finishes reconciling.

### Annotate-only mode (Flux image automation)

Each `gitops-dev`/`gitops-stage`/`gitops-prod` line is normally `<path> <field>`, where
`<field>` is the yq path of the image reference to update. **Omit the field** (provide a
path only) and the action will write the `deploy.staffbase.com/*` annotations **without
touching the image tag**:

```yaml
gitops-stage: |-
  kubernetes/namespaces/my-service/stage/de1/my-service-helm.yaml
```

Use this for apps whose image tag is owned by
[Flux image automation](https://fluxcd.io/flux/components/image/) (ImageRepository /
ImagePolicy / ImageUpdateAutomation), which scans the registry and commits the `tag:`
line back to the GitOps repo itself. The action still needs to stamp the annotations,
because image automation only knows the tag — it never knows the source `commitSha` or
`repositoryFullName` that Swarmia needs for DORA metrics. This also yields a full commit
SHA in every environment, including prod, where image tags (e.g. `2025.50.14`) carry no SHA.

> **Note:** the `version` annotation is set to the freshly built tag, so it may briefly
> lead the actual `tag:` until image automation selects the new build. It converges, and
> the reporter dedupes on `(commitSha, version)`, so it self-heals.

The two-token `<path> <field>` form is unchanged: it updates the image **and** writes the
annotations, exactly as before.

## Inputs

| Name                        | Description                                                                                                                    | Default                                              |
|-----------------------------|--------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------|
| `docker-registry`           | Docker Registry                                                                                                                | `registry.staffbase.com`                                 |
| `docker-registry-api`       | Docker Registry API (used for retagging without pulling)                                                                       | `https://registry.staffbase.com/v2/` |
| `docker-image`              | Docker Image                                                                                                                   |                                                      |
| `docker-custom-tag`         | Docker Custom Tag to be set on the image                                                                                       |                                                      |
| `docker-tag-timestamp`      | Insert a UTC timestamp into `dev`/`main`/`master` branch tags (`dev-<timestamp>-<short-sha>`) to make them sortable for Flux image automation. Enabled by default; set to `'false'` for the legacy `<prefix>-<short-sha>` format | `true`                              |
| `docker-tag-keep-v-prefix`  | Keep the leading `v` on release (`v*`) tags (`v1.2.3` → `v1.2.3`). Default strips it (`v1.2.3` → `1.2.3`) | `false`                                           |
| `docker-username`           | Username for the Docker Registry                                                                                               |                                                      |
| `docker-password`           | Password for the Docker Registry                                                                                               |                                                      |
| `docker-file`               | Dockerfile                                                                                                                     | `./Dockerfile`                                       |
| `docker-build-args`         | List of build-time variables                                                                                                   |                                                      |
| `docker-build-secrets`      | List of secrets to expose to the build (e.g., key=string, GIT_AUTH_TOKEN=mytoken)                                              |                                                      |
| `docker-build-secret-files` | List of secret files to expose to the build (e.g., key=filename, MY_SECRET=./secret.txt)                                       |                                                      |
| `docker-build-target`       | Sets the target stage to build like: "runtime"                                                                                 |                                                      |
| `docker-build-platforms`       | Sets the target platforms for build                                                                                 | linux/amd64 |
| `docker-build-provenance`   | Generate [provenance](https://docs.docker.com/build/attestations/slsa-provenance/) attestation for the build                   | `false`                                              |
| `docker-build-outputs`      | Custom output destinations (e.g. `type=registry,push=true,compression=zstd,force-compression=true`). When set, this replaces the default push behavior — include `push=true` if pushing is desired |                                          |
| `docker-disable-retagging`  | Disables retagging of existing images and run a new build instead                                                              | `false`                                              |
| `gitops-organization`       | GitHub Organization for GitOps                                                                                                 | `Staffbase`                                          |
| `gitops-repository`         | GitHub Repository for GitOps                                                                                                   | `mops`                                               |
| `gitops-user`               | GitHub User for GitOps                                                                                                         | `Staffbot`                                           |
| `gitops-email`              | GitHub Email for GitOps                                                                                                        | `staffbot@staffbase.com`                             |
| `gitops-token`              | GitHub Token for GitOps                                                                                                        |                                                      |
| `gitops-dev`                | Files which should be updated by the GitHub Action for DEV, must be relative to the root of the GitOps repository. Each line is `<path> <field>`; omit `<field>` (path only) to write annotations without touching the image — see [Annotate-only mode](#annotate-only-mode-flux-image-automation) |                                                      |
| `gitops-stage`              | Files which should be updated by the GitHub Action for STAGE, must be relative to the root of the GitOps repository. Each line is `<path> <field>`; omit `<field>` (path only) for [annotate-only mode](#annotate-only-mode-flux-image-automation) |                                                      |
| `gitops-prod`               | Files which should be updated by the GitHub Action for PROD, must be relative to the root of the GitOps repository. Each line is `<path> <field>`; omit `<field>` (path only) for [annotate-only mode](#annotate-only-mode-flux-image-automation) |                                                      |
| `upwind-client-id`          | Upwind Client ID                                                                                                              |                                                      |
| `upwind-organization-id`    | Upwind Organization ID                                                                                                        |                                                      |
| `upwind-client-secret`      | Upwind Client Secret                                                                                                          |                                                      |
| `working-directory`         | The directory in which the GitOps action should be executed. The docker-file variable should be relative to working directory. | `.`                                                  |

## Outputs

| Name            | Description         |
|-----------------|---------------------|
| `docker-digest`  | Digest of the image                                                             |
| `docker-tag`     | Tag of the image                                                                |

## Image tags & Flux image automation

The generated image tag depends on the Git ref:

| Ref | Tag (default) | Tag (`docker-tag-timestamp: 'false'`) | Floating tag |
|-----|---------------|--------------------------------------|--------------|
| `dev` branch | `dev-<utc-timestamp>-<short-sha>` | `dev-<short-sha>` | `dev` |
| `main` branch | `main-<utc-timestamp>-<short-sha>` | `main-<short-sha>` | `main` |
| `master` branch | `master-<utc-timestamp>-<short-sha>` | `master-<short-sha>` | `master` |
| `v*` tag (prod) | the version with the `v` stripped, e.g. `v2025.50.14` → `2025.50.14` (or kept with `docker-tag-keep-v-prefix: 'true'`) | _(unchanged)_ | `latest` |
| other branch | `<short-sha>` (not pushed) | _(unchanged)_ | — |

By default branch tags carry a `YYYYMMDDHHMMSS` (UTC) timestamp inserted before the
SHA. This makes branch tags **sortable** so
[Flux image automation](https://fluxcd.io/flux/components/image/) can pick the
newest build — the Git SHA alone is not orderable. The short SHA is kept for
traceability and Flux sorts on the timestamp only. Set `docker-tag-timestamp: 'false'`
to fall back to the legacy `<prefix>-<short-sha>` shape.

> **Note:** with the timestamp enabled (the default) the build also pushes the plain
> `<prefix>-<short-sha>` tag alongside the timestamped one. That stable per-commit
> tag is what the release step retags into the version tag, so it must continue
> to exist. It does not match the `^<prefix>-[0-9]+-[0-9a-f]+$` filter below, so
> Flux ignores it.

With the timestamp enabled, use one `ImagePolicy` per environment, filtering by prefix:

```yaml
# dev (and likewise main-/master- for stage)
spec:
  imageRepositoryRef: { name: my-service }
  filterTags:
    pattern: '^dev-(?P<ts>[0-9]+)-[0-9a-f]+$'
    extract: '$ts'
  policy:
    numerical: { order: asc }
---
# prod — CalVer tags parse as SemVer (no zero-padding!)
spec:
  imageRepositoryRef: { name: my-service }
  policy:
    semver: { range: '>=0.0.0' }
```

> **Note:** the prod `semver` policy only works if CalVer parts are never
> zero-padded (`2025.5.3`, not `2025.05.03`) — SemVer forbids leading zeros.
> Track the immutable `*-<timestamp>-<sha>` tags, not the floating `dev`/`main`
> tags, so deployments keep their provenance.

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

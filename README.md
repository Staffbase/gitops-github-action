# 🚀 GitHub Action for GitOps

This GitHub Action can be used for our GitOps workflow.
The GitHub Action will build and push the Docker image for your service and deploys the new version at your Kubernetes clusters.

## Requirement

When you want to use this GitHub Action your GitHub repository should have a `dev` and `master` / `main` branch and it should use tags for releases.

- For the `dev` branch we will change the files specified under `gitops-dev`.
- For the `master` / `main` branch we will change the files specified under `gitops-stage`.
- For a new tag the files under `gitops-prod` will be used.

This GitOps setup should be the default for all your repositories.
However, if you have a special case, you can leave `gitops-dev`, `gitops-stage` and `gitops-prod` undefined, then those steps will be skipped.

## Usages

### Build, Push and Deploy Docker Image

```yaml
name: CD

on: [push]

jobs:
  ci-cd:
    name: Build, Push and Deploy

    runs-on: ubuntu-20.04

    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: GitOps (build, push and deploy a new Docker image)
        uses: Staffbase/gitops-github-action@v4
        with:
          docker-username: ${{ secrets.ARTIFACTORY_USERNAME }}
          docker-password: ${{ secrets.ARTIFACTORY_PASSWORD }}
          docker-image: private/diablo-redbook
          gitops-token: ${{ secrets.GITOPS_TOKEN }}
          gitops-dev: |-
            clusters/customization/dev/mothership/diablo-redbook/diablo-redbook-helm.yaml spec.template.spec.containers.redbook.image
          gitops-stage: |-
            clusters/customization/stage/mothership/diablo-redbook/diablo-redbook-helm.yaml spec.template.spec.containers.redbook.image
          gitops-prod: |-
            clusters/customization/prod/mothership/diablo-redbook/diablo-redbook-helm.yaml spec.template.spec.containers.redbook.image
```

### Build and Push Docker Image

```yaml
name: CD

on: [push]

jobs:
  ci-cd:
    name: Build and Push

    runs-on: ubuntu-20.04

    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: GitOps (build and push a new Docker image)
        uses: Staffbase/gitops-github-action@v4
        with:
          docker-username: ${{ secrets.ARTIFACTORY_USERNAME }}
          docker-password: ${{ secrets.ARTIFACTORY_PASSWORD }}
          docker-image: private/diablo-redbook
```

### Deploy Docker Image

```yaml
name: CD

on: [push]

jobs:
  ci-cd:
    name: Deploy

    runs-on: ubuntu-20.04

    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: GitOps (deploy a new Docker image)
        uses: Staffbase/gitops-github-action@v4
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

## Inputs

| Name                        | Description                                                                                                                    | Default                     |
|-----------------------------|--------------------------------------------------------------------------------------------------------------------------------|-----------------------------|
| `docker-registry`           | Docker Registry                                                                                                                | `staffbase.jfrog.io`        |
| `docker-image`              | Docker Image                                                                                                                   |                             |
| `docker-username`           | Username for the Docker Registry                                                                                               |                             |
| `docker-password`           | Password for the Docker Registry                                                                                               |                             |
| `docker-file`               | Dockerfile                                                                                                                     | `./Dockerfile`              |
| `docker-build-args`         | List of build-time variables                                                                                                   |                             |
| `docker-build-secrets`      | List of secrets to expose to the build (e.g., key=string, GIT_AUTH_TOKEN=mytoken)                                              |                             |
| `docker-build-secret-files` | List of secret files to expose to the build (e.g., key=filename, MY_SECRET=./secret.txt)                                       |                             |
| `docker-build-target`       | Sets the target stage to build like: "runtime"                                                                                 |                             |
| `docker-build-provenance`   | Generate [provenance](https://docs.docker.com/build/attestations/slsa-provenance/) attestation for the build                   | `mode=min,inline-only=true` |
| `gitops-organization`       | GitHub Organization for GitOps                                                                                                 | `Staffbase`                 |
| `gitops-repository`         | GitHub Repository for GitOps                                                                                                   | `mops`                      |
| `gitops-user`               | GitHub User for GitOps                                                                                                         | `Staffbot`                  |
| `gitops-email`              | GitHub Email for GitOps                                                                                                        | `staffbot@staffbase.com`    |
| `gitops-token`              | GitHub Token for GitOps                                                                                                        |                             |
| `gitops-dev`                | Files which should be updated by the GitHub Action for DEV, must be relative to the root of the GitOps repository              |                             |
| `gitops-stage`              | Files which should be updated by the GitHub Action for STAGE, must be relative to the root of the GitOps repository            |                             |
| `gitops-prod`               | Files which should be updated by the GitHub Action for PROD, must be relative to the root of the GitOps repository             |                             |
| `working-directory`         | The directory in which the GitOps action should be executed. The docker-file variable should be relative to working directory. | `.`                         |

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct, and the process for submitting pull requests to us.

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

# 🚀 GitHub Action for GitOps

This GitHub Action can be used for our GitOps workflow.
The GitHub Action will build and push the Docker image for your service and deploys the new version at your Kubernetes clusters.

## Requirement

When you want to use this GitHub Action your GitHub repository should have a `dev` and `master` / `main` branch and it should use tags for releases.

- For the `dev` branch we will change the files specified under `gitopsdev`.
- For the `master` / `main` branch we will change the files specified under `gitopsstage`.
- For a new tag the files under `gitopsprod` will be used.

This GitOps setup should be the default for all your repositories.
However, if you have a special case, you can leave `gitopsdev`, `gitopsstage` and `gitopsprod` undefined, then those steps will be skipped.

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
        uses: Staffbase/gitops-github-action@v3
        with:
          dockerusername: ${{ secrets.DOCKER_USERNAME }}
          dockerpassword: ${{ secrets.DOCKER_PASSWORD }}
          dockerimage: private/diablo-redbook
          gitopstoken: ${{ secrets.GITOPS_TOKEN }}
          gitopsdev: |-
            clusters/customization/dev/mothership/diablo-redbook/diablo-redbook-helm.yaml spec.template.spec.containers.redbook.image
          gitopsstage: |-
            clusters/customization/stage/mothership/diablo-redbook/diablo-redbook-helm.yaml spec.template.spec.containers.redbook.image
          gitopsprod: |-
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
        uses: Staffbase/gitops-github-action@v3
        with:
          dockerusername: ${{ secrets.DOCKER_USERNAME }}
          dockerpassword: ${{ secrets.DOCKER_PASSWORD }}
          dockerimage: private/diablo-redbook
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
        uses: Staffbase/gitops-github-action@v3
        with:
          gitopstoken: ${{ secrets.GITOPS_TOKEN }}
          gitopsdev: |-
            clusters/customization/dev/mothership/diablo-redbook/diablo-redbook-helm.yaml spec.template.spec.containers.redbook.image
          gitopsstage: |-
            clusters/customization/stage/mothership/diablo-redbook/diablo-redbook-helm.yaml spec.template.spec.containers.redbook.image
          gitopsprod: |-
            clusters/customization/prod/mothership/diablo-redbook/diablo-redbook-helm.yaml spec.template.spec.containers.redbook.image
```

## Inputs

| Name                 | Description                                                                                                                   | Default                  |
|----------------------|-------------------------------------------------------------------------------------------------------------------------------|--------------------------|
| `dockerregistry`     | Docker Registry                                                                                                               | `registry.staffbase.com` |
| `dockerimage`        | Docker Image                                                                                                                  |                          |
| `dockerusername`     | Username for the Docker Registry                                                                                              |                          |
| `dockerpassword`     | Password for the Docker Registry                                                                                              |                          |
| `dockerfile`         | Dockerfile                                                                                                                    | `./Dockerfile`           |
| `dockerbuildargs`    | List of build-time variables                                                                                                  |                          |
| `dockerbuildtarget`  | Sets the target stage to build like: "runtime"                                                                                |                          |
| `gitopsorganization` | GitHub Organization for GitOps                                                                                                | `Staffbase`              |
| `gitopsrepository`   | GitHub Repository for GitOps                                                                                                  | `mops`                   |
| `gitopsuser`         | GitHub User for GitOps                                                                                                        | `Staffbot`               |
| `gitopsemail`        | GitHub Email for GitOps                                                                                                       | `staffbot@staffbase.com` |
| `gitopstoken`        | GitHub Token for GitOps                                                                                                       |                          |
| `gitopsdev`          | Files which should be updated by the GitHub Action for DEV, must be relative to the root of the GitOps repository             |                          |
| `gitopsstage`        | Files which should be updated by the GitHub Action for STAGE, must be relative to the root of the GitOps repository           |                          |
| `gitopsprod`         | Files which should be updated by the GitHub Action for PROD, must be relative to the root of the GitOps repository            |                          |
| `workingdirectory`   | The directory in which the GitOps action should be executed. The dockerfile variable should be relative to working directory. | `.`                      |

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

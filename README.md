# GitHub Action for GitOps

This GitHub Action can be used for our GitOps workflow.
The GitHub Action will build and push the Docker image for your service and deploys the new version at our Kubernetes clusters.

## Requirement

When you want to use this GitHub Action your GitHub repository should have a `dev` and `master` / `main` branch and it should use tags for releases.
For the `dev` branch we will change the files specified under `gitopsdev`.
For the `master` / `main` branch we will change the files specified under `gitopsstage`.
For a new tag the files under `gitopsprod` will be used.

This GitOps setup (dev -> dev, master -> stage, tag -> prod) should be the default for all our repositories.
However, if you have a special case, you can leave `gitopsdev`, `gitopsstage` and `gitopsprod` undefined, then those steps will be skipped.

## Usage

```yaml
name: Redbook CI/CD

on: [push]

jobs:
  ci-cd:
    name: Build, Push and Deploy

    runs-on: ubuntu-20.04

    steps:
      - name: Checkout
        uses: actions/checkout@v3

      # Run the GitOps GitHub Action which builds and push the Docker image and then updates the deployment in the repository.
      - name: GitOps (build, push and deploy a new Docker image)
        uses: Staffbase/gitops-github-action@v3
        # The DOCKER_USERNAME, DOCKER_PASSWORD and GITOPS_TOKEN secrets are available as organization secret.
        with:
          dockerusername: ${{ secrets.DOCKER_USERNAME }}
          dockerpassword: ${{ secrets.DOCKER_PASSWORD }}
          # This is the name of the Docker image for your service.
          dockerimage: private/diablo-redbook
          # List of build-time variables
          dockerbuildargs: |
            "ARG1='one'"
            "ARG2='two'"
          # Sets the target stage to build
          dockerbuildtarget: "runtime"
          # The additional arguments you need to build the docker image
          gitopstoken: ${{ secrets.GITOPS_TOKEN }}
          # The gitopsdev, gitopsstage and gitopsprod values are used to specify which files including the YAML path which should be updated with the new image.
          # ATTENTION 1: You must use |- to remove the final newline in the string, otherwise the GitHub Action will fail.
          # ATTENTION 2: The file path must be relative to the root of the GitOps repository (default: Staffbase/mops).
          gitopsdev: |-
            clusters/customization/dev/mothership/diablo-redbook/diablo-redbook-helm.yaml spec.template.spec.containers.redbook.image
          gitopsstage: |-
            clusters/customization/stage/mothership/diablo-redbook/diablo-redbook-helm.yaml spec.template.spec.containers.redbook.image
          gitopsprod: |-
            clusters/customization/prod/mothership/diablo-redbook/diablo-redbook-helm.yaml spec.template.spec.containers.redbook.image
          # You can also update multiple file or multiple images in one file.
          # The following example updates the Varnish image in the production cluster for main-de1 and main-us1. It also updates two images one is used for the init container and the other one for the normal container.
          # gitopsprod: |-
          #   clusters/customization/prod/main-de1/mediaserver/varnish-helm.yaml spec.template.spec.initContainers.config.image
          #   clusters/customization/prod/main-de1/mediaserver/varnish-helm.yaml spec.template.spec.containers.varnish.image
          #   clusters/customization/prod/main-us1/mediaserver/varnish-helm.yaml spec.template.spec.initContainers.config.image
          #   clusters/customization/prod/main-us1/mediaserver/varnish-helm.yaml spec.template.spec.containers.varnish.image
```

## Inputs

| Name                          | Description                                                                                                                   | Default                  |
|-------------------------------|-------------------------------------------------------------------------------------------------------------------------------|--------------------------|
| `dockerenabled`               | Build and push the Docker Image                                                                                               | `true`                   |
| `dockerregistry`              | Docker Registry                                                                                                               | `registry.staffbase.com` |
| `dockerimage`                 | Docker Image                                                                                                                  |                          |
| `dockerusername`              | Username for the Docker Registry                                                                                              |                          |
| `dockerpassword`              | Password for the Docker Registry                                                                                              |                          |
| `dockerfile`                  | Dockerfile                                                                                                                    | `./Dockerfile`           |
| `dockerbuildargs`             | List of build-time variables                                                                       |                          |
| `dockerbuildtarget`           | Sets the target stage to build like: "runtime"                                                                                |                          |
| `gitopsenabled`               | Update the manifest files in the GitOps repository                                                                            | `true`                   |
| `gitopsorganization`          | GitHub Organization for GitOps                                                                                                | `Staffbase`              |
| `gitopsrepository`            | GitHub Repository for GitOps                                                                                                  | `mops`                   |
| `gitopsuser`                  | GitHub User for GitOps                                                                                                        | `Staffbot`               |
| `gitopsemail`                 | GitHub User for GitOps                                                                                                        | `staffbot@staffbase.com` |
| `gitopstoken`                 | GitHub Token for GitOps                                                                                                       |                          |
| `gitopsdev`                   | Files which should be updated by the GitHub Action for DEV                                                                    |                          |
| `gitopsstage`                 | Files which should be updated by the GitHub Action for STAGE                                                                  |                          |
| `gitopsprod`                  | Files which should be updated by the GitHub Action for PROD                                                                   |                          |
| `workingdirectory`            | The directory in which the GitOps action should be executed. The dockerfile variable should be relative to working directory. | `.`                      |

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct, and the process for submitting pull requests to us.

## License

This project is licensed under the Apache-2.0 License - see the [LICENSE.md](LICENSE) file for details.

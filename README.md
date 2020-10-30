# GitHub Action for GitOps

This GitHub Action can be used for our GitOps workflow. The GitHub Action will build and push the Docker image for your service and deploys the new version at our Kubernetes clusters.

## Usage

```sh
      - uses: actions/checkout@v2
        with:
          repository: Staffbase/gitops-github-action
          ref: dia-1232-initial-development
          token: ${{ secrets.GITOPS_TOKEN }}
          path: .github/gitops

      - name: Private Action
        uses: ./.github/gitops
        with:
          who-to-greet: 'Rico'
```

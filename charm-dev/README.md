# reusable-justfiles
A collection of reusable justfiles.

## charm-dev
A collection of recipes for setting up a development environment for charmed operators.

Currently available:
- [Ubuntu 24.04](ubuntu-24.04.just)

For a "full install", use the `charm-dev` recipe.

```bash
sudo just -f ubuntu-24.04.just charm-dev
```

For bootstrapping the default controller names and models,

```bash
sudo just -f ubuntu-24.04.just default-models
```

The other major recipes are `microk8s`, `juju`, `startcraft`.

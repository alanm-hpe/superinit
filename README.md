# superinit

`superinit` is a command line utility to perform the tasks necessary to interface with an HPE Cray EX Shasta system.

It's primary tasks are to:
* Install the `cray` and `sat` CLI, if not found in the $PATH
* Configure `cray` to initialize itself with a given friendly system name (ex: lemondrop)
* Derive the Platform CA from the API gateway and add it to the MacOS Keychain
* Authenticate `cray` using a stored value from the MacOS Keychain, or interactively
* Configure `sat` to use the active `cray` config and token
* Optionally print a list of Subject Alternate Names from the Platform CA (Web UIs)

## Installation

Clone this project and add it to your PATH

```bash
git clone https://github.com/alanm-hpe/superinit.git
cd superinit; ./superinit.sh
```

## Usage

To get started, run superinit.sh with no arguments to install `cray` and `sat` in python virtual environments:
```bash
./superinit.sh
```

Once complete, add the following to your PATH:
```
export PATH=${PATH}:$HOME/.config/superinit/cmds/cray_venv/bin
export PATH=${PATH}:$HOME/.config/superinit/cmds/sat_venv/bin
```

With `cray` and `sat` installed, run superinit.sh again and provide the name of a system:
```
./superinit.sh -s lemondrop
```

The command will prompt a couple times to approve various activies:
```bash
superinit -s lemondrop
Could not find craycli lemondrop configuration. Would you like to create one?
1) Yes
2) No
#? 1
Initialization complete.

cray command not authorized. Authorize with 'cray auth login'?
1) Yes
2) No
#? 1
Read Keychain for cray password?
1) Yes
2) No
#? 1
Success!
```
If you'd like to let `superinit.sh` use the MacOS Keychain read your `cray` password, be sure to add a `craycli` password to the Keychain. Otherwise select "No" to interactively type your password.

`superinit.sh` is also able to print a list of Subject Alternate Names (SANs) to list the available Web UI dashboards:
```
./superinit.sh -s lemondrop -u
alertmanager.cmn.lemondrop.hpc.amslabs.hpecorp.net
ara.cmn.lemondrop.hpc.amslabs.hpecorp.net
argo.cmn.lemondrop.hpc.amslabs.hpecorp.net
cmn.lemondrop.hpc.amslabs.hpecorp.net
csms.cmn.lemondrop.hpc.amslabs.hpecorp.net
grafana.cmn.lemondrop.hpc.amslabs.hpecorp.net
jaeger-istio.cmn.lemondrop.hpc.amslabs.hpecorp.net
kiali-istio.cmn.lemondrop.hpc.amslabs.hpecorp.net
opa-gpm.cmn.lemondrop.hpc.amslabs.hpecorp.net
prometheus.cmn.lemondrop.hpc.amslabs.hpecorp.net
sma-grafana.cmn.lemondrop.hpc.amslabs.hpecorp.net
sma-kibana.cmn.lemondrop.hpc.amslabs.hpecorp.net
vcs.cmn.lemondrop.hpc.amslabs.hpecorp.net
```

## Contributing

Pull requests are welcome. For major changes, please open an issue first
to discuss what you would like to change.

Please make sure to update tests as appropriate.

## License

[MIT](https://choosealicense.com/licenses/mit/)

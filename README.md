# runway-powershell-yaml

This module is designed to extend the [Runway PowerShell SDK](https://github.com/runway-software/runway-powershell) to enable importing job definitions in YAML format.

## Installation

```powershell
Install-Module Runway.Yaml -Repository PSGallery
```

This module requires the [Runway module v0.2.0+](https://github.com/runway-software/runway-powershell).

## Example

To see an example of how to use this module, check out our [YAML demo repo](https://github.com/runway-software/yaml-demo)

## YAML definition

In current form, Runway.YAML supports 2 base objects: `jobs` and `connectors`.

### Connectors

A `connectors` block is an object with each property representing a Connector. The property name is used as the name of the Connector. Each connector can have the following properties: `action` and `runner`. Both take one of two properties: `name`, which will be the name of the Action or Runner, and `id`, which will be the Id of the Runner or Action.

If the name is specified, the sync will find the first Runner or Action that matches the name. Actions _should_ have unique names, but for Runners, there is no requirement for them to have a unique name. The way to ensure uniqueness is to specify an Id in both cases. The chances of name overlap is dependent on your environment.

```yaml
connectors:
  "File Server 1"
    action:
      name: download:file
    runner:
      name: FileServer01
    parameters:
      path: C:\path\to\folder
  "File Server 2"
    action:
      id: eb6d5978-25e8-451b-b0bf-6d6e2c6f8820
    runner:
      id: b2cc01f6-f9d6-4db0-b5fd-0aa8e7683af9
    parameters:
      path: C:\path\to\folder
```

### Jobs

A `jobs` block is an object with each property representing a Job. A Job can have the following properties:

- `runners`
- `schedule`
- `actions`

`runners` represent the Runners that will be assigned the Job. They can be specified in 2 formats: an array of names or an array of tags. If an array of names is specified, the names are taken literally and all Runners that have those names will be assigned to the Job. If an array of tags is specified, all Runners that have all of the tags specified will be assigned to the Job.

`schedule` represent the schedule that the Job will run under. It needs the following properties:

- `type` : This can have the following values: `RunEvery`, `RunNow`, `RunOnce`
- `weekdays` : This is a 7 character string, each character represents a day of the week starting with an `M` for Mondays. If they day will be skipped, then a `-` is used instead.
- `time` : This is the time in 24h UTC.
- `repeatMinutes` : This is the number of minutes between each repetition. If `0`, there is no repitition.

`actions` is an array that represents the Actions that the Job should run. The order of the Actions is the order they will be in when the Job is created. Each Action can have the following properties:

- `name` : This is the name of the Action.
- `id` : This is the Id of the Action. This is optional. See Connectors -> Actions to understand uniqueness.
- `parameters` : This is an object and each key value pair is a parameter name and value.
- `connector` : This is a Connector object. You can specify either a `name` or an `id` to target a specific Connector.

## Example

```yaml
connectors:
  "File Server Local Users":
    action:
      name: download:file
    runner:
      name: FileServer01
    parameters:
      Path: E:\Path\To\ReportFolder
      "Use Path": "true"

jobs:
  LocalUsersReport:
    runners:
      tags:
      - Site1
      - Windows
    schedule:
      type: RunEvery
      weekdays: '------S'
      Time: 01:00
      repeatMinutes: "0"
    actions:
    - name: endpoint:getLocalUsers
    - name: download:file
      connector:
        name: File Server Local USers
```
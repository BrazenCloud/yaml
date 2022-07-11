# runway-powershell-yaml
[![Runway.YAML](https://img.shields.io/powershellgallery/v/Runway.YAML.svg?style=flat-square&label=Runway.YAML "Runway.YAML")](https://www.powershellgallery.com/packages/Runway.YAML/)

This module is designed to extend the [Runway PowerShell SDK](https://github.com/runway-software/runway-powershell) to enable importing and exporting job definitions in YAML format.

## Example

Be sure to check out our [Yaml Demo](https://github.com/runway-software/yaml-demo) example repository with several yaml examples and a [Github Actions CI/CD workflow](https://github.com/Runway-Software/yaml-demo/blob/main/.github/workflows/cicd.yaml) that leverages this module.

## Installation

```powershell
Install-Module Runway.Yaml -Repository PSGallery
```

This module requires the [Runway module v0.2.0+](https://github.com/runway-software/runway-powershell).

## Usage

For all usage, you will need to Authenticate to Runway (see the [Runway PowerShell repository](https://github.com/runway-software/runway-powershell)).

### Export YAML

To export a job definition from Runway, you'll need to find the job name or ID and run:

```powershell
Get-RwJobYaml -JobName 'Demo Job'
```

This will return a string in yaml format. To write that to a file you can:

```powershell
Get-RwJobYaml -JobName 'Demo Job' | Out-File .\DemoJob.yaml
```

### Import YAML

To import a job definition into Runway, you'll need to locate the file on your disk or have the yaml loaded already

```powershell
Sync-RwResourceYaml -PathToYaml .\DemoJob.yaml
```

To see an example of how to use this module to import yaml job definitions into Runway, check out our [YAML demo repo](https://github.com/runway-software/yaml-demo)

## YAML definition

In current form, Runway.YAML supports 2 base objects: `jobs` and `connectors`.

### Connectors

A `connectors` block is an object with each property representing a Connector. Each Connector can have the following properties

- `tags`
- `action`
- `runner`
- `parameters`

`tags` takes an array of strings that represents the tags that you want assigned to the Connector.

`action` takes one of two properties: `name`, which will be the name of the Action, or `id`, which will be the Id of the Action. If both are specified, `id` takes priority.

`runner` takes one of two properties: `name`, which will be the name of the Runner, or `id`, which will be the Id of the Runner. If both are specified, `id` takes priority.

If the `name` property is specified, the sync will find the first Runner or Action that matches the name. Due to the way that Runway is designed, Actions will have unique names. However, for Runners, there is no such requirement. The way to guarantee uniqueness is to specify an `id` for runners. The chances of name overlap is dependent on your environment.

`parameters` is an object and each key value pair is a parameter name and value that should be passed to the connector.

```yaml
connectors:
  "File Server 1"
    tags:
      - FileServer
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

A `jobs` block is an object with each property representing a Job. Each Job can have the following properties

- `tags`
- `runners`
- `schedule`
- `actions`

`tags` is an array of strings that represents the tags that you want assigned to the Job.

`runners` represent the Runners that will be assigned the Job. They can be specified in 2 formats: an array of names or an array of tags. If an array of names is specified, the names are taken literally and all Runners that have those names will be assigned to the Job. If an array of tags is specified, all Runners that have all of the tags (tag1 AND tag2 AND tag3, etc) specified will be assigned to the Job.

`schedule` represent the schedule that the Job will run under. It can take the following properties. If properties are not specified, default values will be substituted:

- `type` : This can have the following values: `RunEvery`, `RunNow`, `RunOnce`
- `weekdays` : This is a 7 character string, each character represents a day of the week starting with an `M` for Mondays. If they day will be skipped, then a `-` is used instead.
- `time` : This is the time in 24h UTC.
- `repeatMinutes` : This is the number of minutes between each repetition. If `0`, there is no repitition.

`actions` is an array that represents the Actions that the Job should run. The order of the Actions is the order they will be in when the Job is created. Each Action can have the following properties:

- `name` : This is the name of the Action.
- `id` : This is the Id of the Action. If specified, this takes priority over `name`.
- `parameters` : This is an object and each key value pair is a parameter name and value.
- `connector` : This is a Connector object. You can specify either a `name` or an `id` to target a specific Connector.

## Example

```yaml
connectors:
  "File Server Local Users":
    tags:
      - FileServer
    action:
      name: download:file
    runner:
      name: FileServer01
    parameters:
      Path: E:\Path\To\ReportFolder
      "Use Path": "true"

jobs:
  LocalUsersReport:
    tags:
      - LocalUsers
      - Report
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

## ChangeLog

### 0.1.1

  - Can now retrieve assigned Runners via `-IncludeAssignedRunnersById` or `-IncludeAssignedRunnersByName` on `Get-RwJobYaml`.

### 0.1.0: Initial Release
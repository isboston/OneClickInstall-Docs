[![License](https://img.shields.io/badge/License-GNU%20AGPL%20V3-green.svg?style=flat)](https://www.gnu.org/licenses/agpl-3.0.en.html) 

## Overview

This repo contains scripts to quickly install ONLYOFFICE Docs.

ONLYOFFICE Docs is an open-source office suite that comprises all the tools you need to work with documents, spreadsheets, presentations, PDFs, and PDF forms. The suite supports office files of all popular formats (DOCX, ODT, XLSX, ODS, CSV, PPTX, ODP, etc.) and enables collaborative editing in real time.

Starting from version 6.0, Document Server is distributed under a new name - ONLYOFFICE Docs. 

ONLYOFFICE Docs can be used as a part of [ONLYOFFICE Workspace](#onlyoffice-workspace) or with third-party sync&share solutions (e.g. Nextcloud, ownCloud, Seafile) to enable collaborative editing within their interface.

It has three editions - [Community, Enterprise, and Developer](#onlyoffice-docs-editions).

`docs-install.sh` is used to install ONLYOFFICE Docs Community Edition.

`docs-install.sh -it ENTERPRISE` installs ONLYOFFICE Docs Enterprise Edition.

`docs-install.sh -it DEVELOPER` installs ONLYOFFICE Docs Developer Edition. 

## Functionality

ONLYOFFICE Document Server includes the following editors:

* ONLYOFFICE Document Editor
* ONLYOFFICE Spreadsheet Editor
* ONLYOFFICE Presentation Editor

The editors allow you to create, edit, save and export text, spreadsheet and presentation documents and additionally have the features:

* Collaborative editing
* Hieroglyph support
* Reviewing
* Spell-checking

## Recommended system requirements

* **CPU**: dual-core 2 GHz or higher
* **RAM**: 2 GB or more
* **HDD**: at least 40 GB of free space
* **Swap file**: at least 4 GB
* **OS**: amd64 Linux distribution with kernel version 3.10 or later

## Supported Operating Systems

The installation scripts support the following operating systems, which are **regularly tested** as part of our CI/CD pipelines:
<!-- OS-SUPPORT-LIST-START -->
- RHEL 8
- RHEL 9
- CentOS 8 Stream
- CentOS 9 Stream
- Debian 10
- Debian 11
- Debian 12
- Ubuntu 20.04
- Ubuntu 22.04
- Ubuntu 24.04
<!-- OS-SUPPORT-LIST-END -->

## Installing ONLYOFFICE Docs using the provided script

**STEP 1**: Download the Installation Script:
Download the appropriate OneClickInstall script based on the version you want to install:

- **Enterprise**:
    ```bash
    wget https://download.onlyoffice.com/docs/docs-enterprise-install.sh
    ```
- **Developer**:
    ```bash
    wget https://download.onlyoffice.com/docs/docs-developer-install.sh
    ```
- **Community**:
    ```bash
    wget https://download.onlyoffice.com/docs/docs-install.sh
    ```

**STEP 2**: Install ONLYOFFICE Docs executing the following command:

```bash
bash <script-name>
```

The detailed instruction is available in [ONLYOFFICE Help Center](https://helpcenter.onlyoffice.com/installation/docs-community-install-script.aspx). 

To install Enterprise Edition, use [this instruction](https://helpcenter.onlyoffice.com/installation/docs-enterprise-install-script.aspx). For Developer Edition, use [this one](https://helpcenter.onlyoffice.com/installation/docs-developer-install-script.aspx).

## Project information

Official website: [https://www.onlyoffice.com](https://www.onlyoffice.com/?utm_source=github&utm_medium=cpc&utm_campaign=GitHubDS)

Code repository: [https://github.com/ONLYOFFICE/DocumentServer](https://github.com/ONLYOFFICE/DocumentServer "https://github.com/ONLYOFFICE/DocumentServer")

Docker Image: [https://github.com/ONLYOFFICE/Docker-DocumentServer](https://github.com/ONLYOFFICE/Docker-DocumentServer "https://github.com/ONLYOFFICE/Docker-DocumentServer")

License: [GNU AGPL v3.0](https://onlyo.co/38YZGJh)

ONLYOFFICE Docs on official website: [http://www.onlyoffice.com/office-suite.aspx](http://www.onlyoffice.com/office-suite.aspx?utm_source=github&utm_medium=cpc&utm_campaign=GitHubDS)

## User feedback and support

If you have any problems with or questions about [ONLYOFFICE Document Server][2], please visit our official forum to find answers to your questions: [forum.onlyoffice.com][1] or you can ask and answer ONLYOFFICE development questions on [Stack Overflow][3].

  [1]: https://forum.onlyoffice.com
  [2]: https://github.com/ONLYOFFICE/DocumentServer
  [3]: http://stackoverflow.com/questions/tagged/onlyoffice

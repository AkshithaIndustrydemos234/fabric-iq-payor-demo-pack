# Fabric IQ Payor Demo Pack

Deploys a complete Fabric IQ payor demo into your own tenant. Edit two lines, run one script, about 20 minutes.

| | |
|---|---|
| **You edit** | 2 lines in `Payor_Fabric_deployment.ps1` — workspace name and capacity name |
| **You run** | One PowerShell command |
| **You get** | Workspace, folders, lakehouse, 4 tables, semantic model, ontology, data agent, notebook, pipeline |
| **Afterwards** | 2 required manual steps in the portal (5 minutes) |
---

## 1. Prerequisites

Complete all four before you start.

| Requirement | Verify with | Notes |
|---|---|---|
| Fabric capacity F2 | `fab ls .capacities` | Note the exact capacity name |
| PowerShell 7 | `pwsh --version` | Windows PowerShell 5.1 will not work |
| Python 3.12 | `python --version` | 3.12 specifically — see warning below |
| Fabric CLI 1.7.0+ | `fab --version` | `pip install ms-fabric-cli` |

> ⚠️ **Install Python 3.12, not the latest release.**
> The Fabric CLI fails to install on Python 3.14 — it tries to compile a dependency and demands Visual C++ Build Tools. Download 3.12 from [python.org](https://www.python.org/downloads/release/python-3129/) and tick **"Add python.exe to PATH"** on the first installer screen.

**If both Python 3.12 and a newer version are installed,** target 3.12 explicitly:

```powershell
py -3.12 -m pip install ms-fabric-cli
```

Then open a new terminal and confirm with `fab --version`.

---

## 2. Pack contents

| File or folder | What it is |
|---|---|
| `README.md` | These instructions |
| `Payor_Fabric_deployment.ps1` | The only file you edit and the only file you run |
| `data/` | Four CSV files — the demo dataset |
| `fabric/` | Four Fabric item definitions |

Inside `fabric/`:

| Subfolder | Deploys as | Format |
|---|---|---|
| `caldova_payor_model/` | Semantic model | TMDL |
| `caldova_payor_ontology/` | Ontology | JSON |
| `caldova_payor_agent/` | Data agent | JSON |
| `pl_ingest_enrollment/` | Data pipeline | JSON |

The JSON files are Fabric's own item-definition exports, not hand-written code. Tenant-specific IDs have been replaced with placeholders so the pack works in any tenant. Nothing in `fabric/` needs editing.

Keep the structure exactly as shipped — the script reads these paths directly and will stop if anything is renamed or moved.

---

## 3. Get the pack

**Option A — Download ZIP**

Click **Code → Download ZIP**, then extract.

**Option B — Clone**

```powershell
git clone https://github.com/AkshithaIndustrydemos234/fabric-iq-payor-demo-pack.git
cd fabric-iq-payor-demo-pack
```

---

## 4. Configure — 2 lines

Open `Payor_Fabric_deployment.ps1` and edit the two values at the top:

```powershell
# --- the only lines anyone edits ---
$workspace = "Payor Demo"
$capacity  = "f2westuscapacityq2"
# -----------------------------------
```

| Line | Set to |
|---|---|
| `$workspace` | A name that does not already exist in your tenant |
| `$capacity` | Your capacity name, exactly as shown by `fab ls .capacities` |

Everything else — workspace, lakehouse and ontology IDs — is resolved at runtime. There are no GUIDs to paste.

---

## 5. Deploy

```powershell
pwsh -ExecutionPolicy Bypass -File .\Payor_Fabric_deployment.ps1
```

The `ExecutionPolicy` flag applies to this run only and changes nothing on your machine.

**What to expect:**

1. A browser opens — sign in with your Fabric account. Signing in is how the tenant is chosen.
2. The script prints the signed-in tenant and pauses. Confirm, then press **Enter**.
3. Items are created in order, with progress printed as it goes.
---

## 6. Manual steps

Three steps cannot be automated. These are current Fabric limitations, not gaps in the script.

### Step 1 — Load the graph model — **REQUIRED**

> The data agent will not answer questions until this is done. It replies that the graph model is not ready.

1. Open the graph model created alongside the ontology in your new workspace.
2. Click **Save**. Change nothing.
3. Wait for the data to load.

A graph model created through the API is structurally complete but not queryable until opened once in the portal, which provisions its loading infrastructure.

### Step 2 — Add ontology descriptions and synonyms — **OPTIONAL**

Open the ontology and add a description and synonyms to each entity type and relationship type. This is the business vocabulary the data agent uses to interpret questions — answers are noticeably weaker without it.

This metadata is not part of the ontology definition schema, so it cannot be deployed.

### Step 3 — Apply a task flow — **RECOMMENDED**

In the workspace list view: **Select a predesigned task flow** → **Medallion** → assign the deployed items to tasks. Purely presentational; task flows have no API.

---

## 7. Validation

### 7.1 In the Fabric portal

Open the data agent in your workspace and ask each prompt in turn.

| # | Prompt | What a good answer looks like |
|---|---|---|
| 1 | Show the application mix by status. | A breakdown across Enrolled, In progress, New and Exception, totaling 50 applications. |
| 2 | List the failed eligibility checks across all applications. | The specific checks that failed, with the applications they belong to. |

If the agent replies that the graph model is not ready, return to **Step 1** of the manual steps.

### 7.2 Publish the agent to Microsoft 365 Copilot

1. Open the data agent in your Fabric workspace.
2. Select **Publish**.
3. Once published, open Microsoft 365 Copilot and select the agent.

### 7.3 In Microsoft 365 Copilot

| # | Prompt | What a good answer looks like |
|---|---|---|
| 1 | Executive summary: manual vs automated enrollment performance | A narrative comparison drawing on enrollment status, eligibility outcomes and plan mix. |

A weak or generic answer usually means the ontology descriptions and synonyms have not been added. See **Step 2** of the manual steps.

---

## 8. Verify

| Check | Expected |
|---|---|
| Workspace item list | 9 items across 4 folders |
| Lakehouse tables | 4 tables, each with data |
| Semantic model | Tables show columns, no error banner |
| Ontology | 4 entity types, 3 relationships, columns bound |
| Graph model | Data loaded (after step 1) |
| Data agent | Answers a question about the data |
| Pipeline | 8 activities on the canvas |

---

## 9. Known issues

| Issue | Cause | Fix |
|---|---|---|
| `pip install ms-fabric-cli` fails asking for Microsoft Visual C++ 14.0 or greater | Python 3.14 is installed. The CLI has a dependency with no prebuilt package for 3.14, so pip tries to compile it. | Install Python 3.12 and install the CLI under it. Do not install Visual C++ Build Tools. |
| The data agent replies that the graph model is not ready | The graph model has not been opened and saved in the portal. | Complete **Step 1** of the manual steps. |
| Workspace name may already exist | The name in `$workspace` is taken. | Pick a different name. |
| Lakehouse ID could not be resolved | The capacity name is wrong. | Check against `fab ls .capacities`. |


---

## 10. Questions

| Question | Answer |
|---|---|
| Can I run it more than once? | Yes — use a different workspace name each time |
| Does it cost anything? | No. You consume only your own Fabric capacity |
| Are credentials stored? | No. Sign-in is an interactive browser prompt |
| Can I change the demo data? | Replace the CSVs, but keep the column names |
| How do I remove it? | Delete the workspace — that removes all 9 items |
| Can I use an existing workspace? | No. The script creates its own |
| Is there any application code? | No. One PowerShell script of CLI commands, plus data and declarative definitions |

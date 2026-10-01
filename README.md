# Fabric IQ Payor Demo Pack

Deploys a complete Fabric IQ payor demo into your own tenant. Edit two lines, run one script, about 20 minutes.

| | |
|---|---|
| **You edit** | 2 lines in `Payor_Fabric_deployment.ps1` — workspace name and capacity name |
| **You run** | One PowerShell command |
| **You get** | Workspace, 4 folders, lakehouse, 4 tables, semantic model, ontology, data agent, notebook, pipeline |
| **Afterwards** | 2 required steps in the Fabric portal (about 5 minutes) |

---

## 1. Prerequisites

Complete every item below before you start.

| Requirement | Verify with | Notes |
|---|---|---|
| Fabric Administrator role | Microsoft 365 admin center → Roles → Fabric Administrator | Assign it to the user running the deployment. Needed to change tenant settings. |
| Tenant setting | Fabric Admin portal → Tenant settings | Enable **Users can create Ontology (preview) items**. |
| Microsoft 365 E5 license | Microsoft 365 admin center → your license assignment | Assigned to the same user. |
| Fabric capacity (F2) — Capacity Administrator | `fab ls .capacities` | Paid F2 or higher. You must be a Fabric Capacity Administrator on it. Note the exact name for `$capacity`. |
| PowerShell 7 | `pwsh --version` | Windows PowerShell 5.1 will not work. |
| Python 3.12 | `py -3.12 --version` | Python 3.10 to 3.13 is supported (tested on 3.12 and 3.13). 3.14 is not supported. |
| Fabric CLI | `fab --version` | `py -3.13 -m pip install ms-fabric-cli` |

> ⚠️ **Install Python 3.13, not the latest release.**
> The Fabric CLI fails to install on Python 3.14 — it tries to compile a dependency and asks for Visual C++ Build Tools.

### Installing Python 3.13

1. Download the Windows installer (64-bit) from [python.org](https://www.python.org/downloads/release/python-3120/) and run it.
2. On the first screen, tick **Add python.exe to PATH**. Do not click **Install Now** yet.
3. Click **Customize installation**, then **Next** on **Optional Features**.
4. On **Advanced Options**, make sure **Add Python to environment variables** is ticked, then click **Install**.

Already installed without that option? Run the installer again (or **Settings → Apps → Python 3.13 → Modify**), choose **Modify**, click **Next**, tick **Add Python to environment variables**, then **Install**.

### Installing the Fabric CLI

Install the CLI under Python 3.13, even if a newer Python is also on the machine:

```powershell
py -3.13 -m pip install ms-fabric-cli
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

Keep the folder structure exactly as shipped — the script reads these paths directly and will stop if anything is renamed or moved.

---

## 3. Get the pack

> **Note:** the pack is moving to Kevin's repository. The links below will be updated once the move is complete.

**Option A — Download ZIP**

1. Click **Code → Download ZIP**, then extract it.
2. Right-click the extracted `fabric-iq-payor-demo-pack` folder and select **Open in Terminal**.

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
$workspace = "Payor"
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

1. When asked how to authenticate the Fabric CLI, choose **Interactive with a web browser** and press **Enter**. Signing in is how the tenant is chosen.
2. The script prints the signed-in tenant and pauses. Confirm, then press **Enter**.
3. Items are created in order, with progress printed as it goes.

> **Long pauses are expected.** The script waits 60 seconds for the SQL endpoint, 45 seconds after each table load, and up to five times 90 seconds if the capacity is busy. A quiet terminal does not mean it has hung — do not press Ctrl+C.

---

## 6. Finish the setup in the portal

Four steps cannot be deployed through the API. Saving the graph model and publishing the agent are current Fabric limitations, task flows have no API, and descriptions and synonyms are not part of the ontology definition.

| Step | Task | Priority |
|---|---|---|
| 1 | Save the graph model | **Required** |
| 2 | Publish the data agent | **Required** for Microsoft 365 Copilot |
| 3 | Add descriptions and synonyms | Recommended |
| 4 | Apply a task flow | Optional |

### Step 1 — Save the graph model — **Required**

> The data agent will not answer questions until this is done. It replies that the graph model is not ready.

1. Open the graph model created alongside the ontology in your new workspace.
2. Click **Save**. Change nothing.
3. Wait for the data to finish loading.

A graph model created through the API is structurally complete but not queryable until it is opened and saved once in the portal.


### Step 2 — Add descriptions and synonyms — **Recommended**

Open the ontology and add a description and synonyms to each entity type and relationship type. This is the business vocabulary the data agent uses to interpret questions — answers are noticeably weaker without it.

### Step 3 — Apply a task flow — **Optional**

In the workspace list view: **Select a predesigned task flow** → **Medallion** → assign the deployed items to tasks. Purely presentational.

### Step 4 — Publish the data agent — **Required for Microsoft 365 Copilot**

1. Open the data agent in your Fabric workspace.
2. Select **Publish**. A dialog opens.
3. Turn on **Also publish to Microsoft 365 Copilot**, then select **Publish**.
4. Once published, open Microsoft 365 Copilot and select the agent.

---

## 7. Check what was created

| Folder | Items |
|---|---|
| 01 Sources | `payor_lh` + 4 Delta tables |
| 02 Ingestion | `NB_Payor_Demo`, `PL_Ingest_Enrollment` |
| 03 Insights | `caldova_payor_model`, `caldova_payor_ontology` |
| 04 Operational | `caldova_payor_agent` |

| Check | Expected |
|---|---|
| Workspace item list | 9 items across 4 folders |
| Lakehouse tables | 4 tables, each with data |
| Semantic model | Tables show columns, no error banner |
| Ontology | 4 entity types, 3 relationships, columns bound |
| Graph model | Data loaded (after Step 1 in section 6) |
| Data agent | Present in 04 Operational (answers are tested in section 8) |
| Pipeline | 8 activities on the canvas |

---

## 8. Validate the demo

### 8.1 In the Fabric portal

Open the data agent in your workspace and ask each prompt in turn.

| # | Prompt | What a good answer looks like |
|---|---|---|
| 1 | Show the application mix by status. | A breakdown across Enrolled, In progress, New and Exception, totaling 50 applications. |
| 2 | List the failed eligibility checks across all applications. | The specific checks that failed, with the applications they belong to. |

If the agent replies that the graph model is not ready, return to **Step 1** in section 6.

### 8.2 In Microsoft 365 Copilot

Ask the published agent (section 6, Step 2):

| # | Prompt | What a good answer looks like |
|---|---|---|
| 1 | Executive summary: manual vs automated enrollment performance | A narrative comparison drawing on enrollment status, eligibility outcomes and plan mix. |

A weak or generic answer usually means the ontology descriptions and synonyms have not been added. See **Step 3** in section 6.

---

## 9. Troubleshooting

| Issue | Cause | Fix |
|---|---|---|
| `pip install ms-fabric-cli` fails asking for Microsoft Visual C++ 14.0 or greater, or `fab` is not recognized | Python 3.14 is installed. The CLI has a dependency with no prebuilt package for 3.14, so pip tries to compile it. | Install Python 3.12 and install the CLI under it. Do not install Visual C++ Build Tools. |
| The data agent replies that the graph model is not ready | The graph model has not been opened and saved in the portal. | Complete **Step 1** in section 6. |
| The run stops at stage 1 with an ID-resolution error | The workspace name in `$workspace` already exists. The script cannot reuse an existing workspace. | Set `$workspace` to a new name and run again. |
| Repeated "Capacity busy. Waiting 90 seconds…" lines | The capacity is throttling. | Normal for up to five attempts. If all five fail, the run stops — try again with a new workspace name once the capacity is less busy. |

---

## 10. Questions

| Question | Answer |
|---|---|
| Can I run it more than once? | Yes — use a different workspace name each time. The script has no cleanup step and cannot rerun into the same workspace. |
| Does it cost anything? | No AI credits. It uses only your own Fabric capacity. |
| Are credentials stored? | No. Sign-in is an interactive browser prompt. |
| Can I change the demo data? | Replace the CSVs, but keep the column names. |
| How do I remove it? | Delete the workspace — that removes all 9 items. |
| Can I use an existing workspace? | No. The script creates its own. |
| Is there any application code? | No. One PowerShell script of CLI commands, plus data and declarative definitions. |

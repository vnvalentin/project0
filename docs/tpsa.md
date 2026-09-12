# TPSA — TPS and Agile

> "We cannot effectively practice Agile without using TPS Thinking Way."

TPS principles mapped to agile software delivery. These shape both how a team builds and how its product behaves toward its customers. This document draws from the global TPSA Guidebook (V1) produced by OMDD and the Toyota Global Agile community.

---

## The Thinking Way

TPS and Agile share a common spirit. While the terminology differs, the purpose, goals, and intention behind the concepts and practices are the same. The TPSA is not about reconciling two separate systems — it is about recognizing that Agile IS TPS applied to knowledge work.

### What is TPS?

- It is a Production System
- It is a Logistics System
- **It is a HUMAN Resources Development System** — this is the most important to understand

### Akio Toyoda's View

> "Often at Toyota, TPS is considered the process of making things more efficient. But I think the purpose should be to make someone's work easier. I believe that is the most reasonable way of understanding what it's really about."

> "We only have 24 hours in a day. Knowing this, supervisors must make the work being done by team members as meaningful as possible. Increasing work that adds value while reducing work processes that are redundant or cause people to wait. My personal take on TPS is that it is 'centered on people.'"

TPS origin: Sakichi Toyoda's desire to ease his mother's burden at the loom — not productivity improvement — led to Jidoka. Improving productivity was secondary to improving the human condition.

### Flow Efficiency Before Resource Efficiency

> "First, make it Flow; Secondly, make it efficient. If we do this in the wrong order, it is very hard to be successful."

- **Resource efficiency** optimizes utilization of individual skills/tools/teams
- **Flow efficiency** optimizes the time from demand raised to demand delivered
- TPS focuses on flow efficiency FIRST, then keeps resource efficiency in mind
- This is a mindset change: prioritize lead time to customer over keeping everyone busy

---

## The 9 Top Concepts of TPS

| Concept | Japanese | Role |
|---------|----------|------|
| Customer First | — | People (top) |
| Stakeholder Satisfaction | — | People (top) |
| Make People | Hitozukuri | People (top) |
| Just in Time | JIT | Pillar |
| Stop in Time | Jidoka | Pillar |
| Safety First | — | Foundation |
| Continuous Improvement | Kaizen | Foundation |
| Visualization | Mieruka | Foundation |
| Make Things | Monozukuri | Foundation |

---

## The 12 Tangen (OMDD Teaching Structure)

1. **Jidoka** — Stop work when there is a defect or when work is complete so that quality is built into the process and muda is not passed on to the next process.

2. **Just-In-Time (JIT)** — Produce and convey only what is needed, when it is needed, in the exact amount needed so that we can realize reduced lead time.

3. **Standardized Work (SW)** — Create a standard process for the desired outcome so that we have a baseline for continuous improvement activities.

4. **Kanban** — Manage the production methods with rules that define how material/components/products and information flow through the process so that a team/group/organization can achieve Just-In-Time.

5. **JIT Logistics** — Apply the concept of delivering only what is needed, when it is needed, in the amount needed to internal and external suppliers so that we can level production flow based on customer demand.

6. **Small Lot Production** — Reduce the size of the work to enable continuous flow so that we can increase flexibility without impacting cost & quality.

7. **Flexible Manpower Line (FML)** — Create a process flexible enough to adapt to frequent changes so that we can produce the right volume to satisfy customer demand.

8. **Material & Information Flowchart (MIFC)** — Draw a visual representation of the process flow so that we can understand the lead time and identify constraints.

9. **Line Capacity** — Define the volume of product able to be produced over a given duration so that we can meet customer demand in the most efficient way possible.

10. **How to Design the Layout (Process)** — Make the process flow, then make the process efficient so that we can consistently deliver a product with safety and quality built in that delights the customer.

11. Solve problems at the root using Toyota Business Practices (TBP) so that we can implement effective countermeasures and prevent recurrence.

12. Build quality into each process through Jikoutei-Kanketsu (JKK) ownership so that defects are contained immediately and never passed to the next proces

---

## TPS in IT — Jidoka Applied

### Quality Control & Short Feedback Loops

A safe process means:
- "I know what is expected of me"
- "I can ask for help/clarification from my peers or team leader"
- "I can propose improvements to my process, and I know my proposals will be listened to & taken seriously"

Jidoka in IT = automated quality gates (CI pipelines, pre-commit hooks, linters, test suites) that stop the line when an abnormality is detected. The point is not having tests — it's making running them trivially cheap so they run frequently.

### Pulling the Andon-cord

- **Social mechanism**: Daily Scrum — team members identify abnormalities and stop
- **Technical mechanism**: CI pipeline stops on failure, notifies team, they inspect and solve
- Team members must be able to "pull the andon with confidence" — knowing someone will respond

### Continuous Integration as Flow Enabler

Working in small increments and integrating frequently gives almost instant feedback. Failure to do so leads to "integration hell." CI enables flow across multiple teams by detecting incompatibilities immediately.

---

## TPS in IT — JIT Applied

### What is a flow unit in IT?

- An incident ticket
- A user request for an application change
- A technical upgrade or patch
- A feature increment

Flow efficiency = measure and optimize the time from demand raised until delivered. This is our primary metric.

---

## Embodying TPSA in Practice

| Tangen | Application |
|--------|-------------|
| Jidoka | Stop work on confusion or defect — clarify, don't proceed with uncertainty. Pre-push hooks and CI gates prevent defects from shipping. |
| JIT | Only do what's needed at this moment. Never flood. Progressive disclosure. |
| Standardized Work | A shared contract standardizes how every surface is described and rendered — one schema, one path. Consistent quality across the product. |
| Kanban | Work state managed with explicit WIP — one item at a time, pull-based advancement. |
| Small Lot | Small work batches. Small PRs. Small deployments. |
| FML | Flexible logic adapts the path to demand — skip what's not relevant. |
| MIFC | Transcripts and logs visualize the full flow. Telemetry maps lead time and constraints. |
| Line Capacity | Know your throughput: units per cycle, cycles per day, time to completion. |
| Layout | Make the flow first, then optimize for efficiency. |

---

## The Three Key Processes (Concurrent Lanes)

> "To build a Tool for People, we must first deeply understand the people we serve. The Customer Process is the foundation of value creation — it is the human journey that dictates everything we do."

### Framework

Three concurrent process lanes run simultaneously for any value stream. They are never sequential. Every observable action maps to exactly one lane.

| Lane | Signal | Classification Test | Core Metric |
|------|--------|-------------------|-------------|
| **1. Customer Process** | What the customer does and feels | "Who is acting?" → Customer acting/waiting/deciding | Time to value, friction points |
| **2. Product Behavior** | How the system operates | "Who is acting?" → System routing/deciding/processing | Muri eliminated, queues imposed |
| **3. Delivery / Learning** | The organizational learning loop | "Who is acting?" → Team learning/improving/fixing | Cost per Learning, Atomic Batch Index |

### Lane 1: Customer Process (Human Intent & Experience)

The end-to-end journey a customer takes to accomplish their goal. This lane exists BEFORE any product exists — the product is a countermeasure to serve this pre-existing human journey.

**Boundary:** Include if a customer is actively doing, deciding, waiting, or experiencing an outcome. Exclude system internals with no customer perception.

**Example:** The customer's journey from "I have a new need" through "my request is complete and my outputs are delivered." Their actions, decisions, confusion, waits, and resolution.

**Required mapping:** Trigger & end condition, customer goal, queues/waits/rework loops, measures of success (1-2 primary + 2-4 guardrails).

### Lane 2: Product Behavior Process (System Execution)

The observed runtime behavior of the product while actively being used. Its mission: eliminate Muri (cognitive overburden) at the point of work.

**Boundary:** Include if it describes runtime data flows, system decisions, state changes, queues, retries, or dependencies. Exclude team improvement work and customer intent.

**Three failure patterns:**
- System queues forcing "Wait" into the customer journey (Muda)
- Complexity not abstracted away (Muri — cognitive overburden)
- Failure states that blame the user (violates Zen Validation)

**Example:** Business logic, processing pipelines, state management, computation, output routing. The system must be invisible — customers experience flow, not machinery.

**Required mapping:** Inputs & outputs, key states & decisions, system queues & failure states, evidence points (telemetry), measures & stop signals (Andon thresholds).

### Lane 3: Delivery / Learning Process (Team Improvement)

The organization's continuous engine for capturing knowledge. The product is a temporary countermeasure — the true engine is organizational learning velocity.

**Boundary:** Include if it describes detecting gaps, formulating hypotheses, running experiments, measuring, reflecting (Hansei), or updating standards. Exclude live runtime behavior and customer intent.

**Example:** TBP problem-solving, short atomic experiments, kaizen reflections, test and eval suites, telemetry analysis, documentation updates.

**Required mapping:** Learning triggers, stages of learning, learning friction (queues & rework), measures of velocity (CpL, Atomic Batch Index).

### Lane Integrity Rules

1. **Never mix lanes.** Always ask "Who is acting?" to classify.
2. **Customer Process is foundational.** Lanes 2 and 3 exist to serve Lane 1.
3. **Product is temporary.** The learning loop is permanent.
4. **Zen Validation spans all lanes.** Never blame the user.
5. **Sensei Mode.** Guide so the correct path is the easiest path.

---

## Glossary (from TPSA Guidebook)

- **Muda** — Waste (time, resources, quality). Seven types: Overproduction, Inventory, Motion, Defects, Over-processing, Waiting, Transportation.
- **Jidoka** — Autonomation for consistently high quality, efficiency, and prevention of defects.
- **JKK (Jikoutei-Kanketsu)** — Built-in quality with ownership.
- **Heijunka** — Leveling by volume and variation; minimizing resources to meet demand while reducing stagnation.
- **SMED** — Single Digit Minute Exchange of Dies; changeover cost/time reduction.
- **Takt Time** — Required assembly duration to match customer demand.
- **Kaizen** — Continuous improvement of work practices.
- **Andon** — Visual tool to signal a problem and alert those who need to act.
- **MIFC (Monojo)** — Value stream map visualizing flow of materials and information.

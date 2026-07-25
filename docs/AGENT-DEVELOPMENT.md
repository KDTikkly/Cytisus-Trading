# Agent Development

Agent assistance is constrained to an algorithm project selected by the user.

An Agent may:

- propose changes to allowlisted project text files;
- explain a patch;
- request a bounded validation or compute job;
- inspect job output already attached to that project.

An Agent may not:

- invoke a shell;
- choose an unapproved interpreter;
- read arbitrary files or credential stores;
- escape the project root;
- download or install runtimes;
- change authorization, risk, or execution-gateway code;
- call Longbridge CLI;
- submit orders.

Patch requests include a rationale and estimated token cost. The application enforces a configured ceiling before a new project version is accepted.

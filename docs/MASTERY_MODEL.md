# Mastery Model

Mastery is bounded to 0-100. On each quiz attempt, `new = old * 0.6 + attempt_score * 0.4`; the first attempt uses its score. This is explainable, deterministic and updated per knowledge label. Task completion and learning time are exposed in stats and can be incorporated in a future weighted revision without changing the API.

# Database

`server/app/main.py:migrate()` creates the versioned schema for users, refresh tokens, knowledge bases, documents, chunks, conversations/messages, plans/tasks, quizzes/attempts, mastery and repository imports. Foreign keys and the `(user_id, knowledge)` mastery key enforce ownership and uniqueness. The development migration is deterministic and runs before the app serves requests.

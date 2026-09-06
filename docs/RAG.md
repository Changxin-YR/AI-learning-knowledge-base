# RAG

Uploads are validated by safe basename, extension and size. Text is split at headings/paragraph boundaries, stored with document and section metadata, and ranked by reproducible token overlap. Chat responses include the selected chunk id, filename, section and preview as citations. `/chat/stream` emits tool, message and done SSE events.

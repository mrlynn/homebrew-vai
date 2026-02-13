# Homebrew Tap for VAI (Voyage AI CLI)

This is the official [Homebrew](https://brew.sh/) tap for **vai** — a CLI toolkit for building RAG pipelines with Voyage AI embeddings and MongoDB Atlas Vector Search.

## Installation

```bash
brew tap mrlynn/vai
brew install vai
```

## Upgrading

```bash
brew update
brew upgrade vai
```

## Uninstalling

```bash
brew uninstall vai
brew untap mrlynn/vai
```

## What is vai?

vai (voyageai-cli) is a comprehensive toolkit that provides:

- **22 CLI commands** for end-to-end RAG workflows
- **Web Playground** for interactive experimentation
- **Desktop App** with OS keychain integration
- **Embedding, chunking, vector search, and reranking** in a single tool

### Quick Start

```bash
# Configure your API keys
vai config set api-key YOUR_VOYAGE_AI_KEY
vai config set mongodb-uri YOUR_MONGODB_URI

# Run the guided demo
vai demo

# Build a RAG pipeline from documents
vai pipeline ./docs/ --db myapp --collection knowledge --create-index

# Search your knowledge base
vai query "How does authentication work?" --db myapp --collection knowledge
```

### Learn More

- **Repository:** [github.com/mrlynn/voyageai-cli](https://github.com/mrlynn/voyageai-cli)
- **npm:** [npmjs.com/package/voyageai-cli](https://www.npmjs.com/package/voyageai-cli)
- **Website:** [vai.mlynn.org](https://vai.mlynn.org)

## For Maintainers

### Updating the Formula

When a new version of voyageai-cli is published to npm:

1. Get the new tarball URL:
   ```bash
   curl -s https://registry.npmjs.org/voyageai-cli/latest | jq -r '.dist.tarball'
   ```

2. Compute the SHA256:
   ```bash
   curl -sL "$(curl -s https://registry.npmjs.org/voyageai-cli/latest | jq -r '.dist.tarball')" | shasum -a 256
   ```

3. Update `Formula/vai.rb` with the new URL, version, and SHA256.

4. Test locally:
   ```bash
   brew install --build-from-source ./Formula/vai.rb
   brew test vai
   brew audit --strict vai
   ```

5. Commit and push. Users will get the update on their next `brew update`.

### Automated Updates (GitHub Actions)

See `.github/workflows/update-formula.yml` for the automated update workflow that checks for new npm releases and creates PRs to update the formula.

## License

MIT

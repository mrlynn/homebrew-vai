require "language/node"

class Vai < Formula
  desc "CLI toolkit for RAG pipelines with Voyage AI embeddings and MongoDB Atlas Vector Search"
  homepage "https://github.com/mrlynn/voyageai-cli"
  # Update the URL and sha256 with each new release.
  # To get the tarball URL: https://registry.npmjs.org/voyageai-cli/-/voyageai-cli-<VERSION>.tgz
  # To compute sha256: curl -sL <URL> | shasum -a 256
  url "https://registry.npmjs.org/voyageai-cli/-/voyageai-cli-1.29.0.tgz"
  sha256 "ca15922f279a5b6e9f5ed5d49b3ad6072a8c90bcf00f1a4323df347fb995d0ab"
  license "MIT"

  livecheck do
    url "https://registry.npmjs.org/voyageai-cli/latest"
    regex(/"version"\s*:\s*"([^"]+)"/i)
  end

  depends_on "node"

  def install
    system "npm", "install", *Language::Node.std_npm_install_args(libexec)
    bin.install_symlink Dir["#{libexec}/bin/*"]

    # Generate shell completions if the CLI supports it
    generate_completions_from_executable(bin/"vai", "completions", shells: [:bash, :zsh])
  end

  def caveats
    <<~EOS
      To get started with vai, configure your API keys:

        vai config set api-key YOUR_VOYAGE_AI_KEY
        vai config set mongodb-uri YOUR_MONGODB_URI

      Or set environment variables:

        export VOYAGE_API_KEY=pa-...
        export MONGODB_URI=mongodb+srv://...

      Run `vai demo` for a guided walkthrough.
      Run `vai explain embeddings` to learn about embeddings.
    EOS
  end

  test do
    assert_match "vai", shell_output("#{bin}/vai --version")

    # Test that the help command works
    assert_match "Usage:", shell_output("#{bin}/vai --help")

    # Test that models command lists available models (no API key needed)
    assert_match "voyage", shell_output("#{bin}/vai models 2>&1", 0)
  end
end

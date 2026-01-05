# Algorithmic Trading Strategies: LaTeX Paper

This directory contains a comprehensive LaTeX paper documenting all MQL5 Expert Advisors and TradingView Pine Script strategies.

## Structure

```
paper/
├── main.tex                 # Main LaTeX document
├── chapters/
│   ├── introduction.tex     # Introduction and overview
│   ├── mql5_basics.tex     # MQL5 programming fundamentals
│   ├── algorithms.tex      # Detailed algorithm analysis
│   ├── tradingview.tex     # TradingView Pine Script strategies
│   ├── profitability.tex   # Why strategies make money
│   └── conclusion.tex      # Conclusion and future directions
└── README.md               # This file
```

## Compilation

### Prerequisites

You need a LaTeX distribution installed:
- **Windows**: MiKTeX or TeX Live
- **macOS**: MacTeX
- **Linux**: TeX Live

### Compiling the Document

#### Using pdflatex (Recommended)

```bash
cd paper
pdflatex main.tex
pdflatex main.tex  # Run twice for references
```

#### Using Overleaf (Online)

1. Upload all files to Overleaf
2. Set main.tex as the main document
3. Click "Compile"

#### Using VS Code with LaTeX Workshop

1. Install LaTeX Workshop extension
2. Open main.tex
3. Press Ctrl+Alt+B (or Cmd+Option+B on Mac) to build

### Build Process

The document requires two compilation passes:
1. First pass: Generates content and collects references
2. Second pass: Resolves cross-references and table of contents

## Contents

The paper covers:

1. **Introduction**: Overview of algorithmic trading and strategy categories
2. **MQL5 Basics**: Programming fundamentals, indicator management, trading operations
3. **Algorithms**: Detailed analysis of 13+ Expert Advisors:
   - RSI Reversal strategies (AUD/USD, EUR/USD)
   - RSI Scalping strategies (XAU/USD, Equities)
   - EMA-based strategies
   - Darvas Box breakout system
   - Multi-strategy systems
4. **TradingView**: Pine Script implementation analysis
5. **Profitability**: Theoretical foundations and why strategies work
6. **Conclusion**: Summary and future directions

## Features

- **Code Listings**: Syntax-highlighted MQL5 and Pine Script code
- **Mathematical Formulations**: Equations for indicators and metrics
- **Tables**: Strategy comparisons and performance metrics
- **Cross-References**: Internal links between sections
- **Bibliography**: References to key trading literature

## Customization

### Adding New Algorithms

1. Add algorithm description to `chapters/algorithms.tex`
2. Include code examples using `\lstlisting` environment
3. Update strategy comparison table if needed

### Modifying Style

Edit `main.tex` to customize:
- Document class options
- Page margins
- Code listing styles
- Bibliography style

## Troubleshooting

### Missing Packages

If compilation fails with "Package not found" errors:
- Install missing packages via your LaTeX distribution's package manager
- Or use `tlmgr` (TeX Live): `tlmgr install <package-name>`

### Reference Errors

If references don't resolve:
- Run `pdflatex` twice
- Or use `latexmk -pdf main.tex` for automatic multiple passes

### Code Listing Issues

If code listings don't appear:
- Ensure `listings` package is installed
- Check that code blocks are properly formatted
- Verify file paths in `\lstinputlisting` commands (if used)

## Output

The compiled document will be:
- **main.pdf**: Complete paper with all sections
- Approximately 50-60 pages (depending on content)
- Professional academic formatting
- Ready for printing or digital distribution

## License

This paper documents algorithms from the profitable-expert-advisor repository. Refer to the main repository for licensing information.

## Contributing

To improve the paper:
1. Edit relevant `.tex` files
2. Maintain consistent formatting
3. Test compilation before submitting
4. Update this README if structure changes

## Contact

For questions about the algorithms, refer to the main repository documentation.

# Publication and Google Scholar workflow

This project should be published as two related objects: the software release and the technical report. Keep them linked, but do not pretend that a GitHub repository is itself a peer-reviewed paper.

## 1. Stabilise the scholarly identity

Use one paper title everywhere:

`Bayesian Learning and Model Risk in a Binary Market-Making Model`

Use this subtitle in the PDF if desired:

`A Reproducible Computational Note on Adverse Selection, Misspecification, and Regime Change`

Author name:

`Mohamed Rayan Bouchaibi`

Affiliation:

`Bachelor's student in Mathematics, Ecole polytechnique federale de Lausanne (EPFL)`

Status line on the first page:

`Technical report. Not peer reviewed.`

Do not add a lab, supervisor, ORCID, DOI, or EPFL email address unless each item is real and belongs to you.

## 2. Reproduce before releasing

After applying the code and paper changes, run the repository's full reproducibility workflow from a clean environment. The regenerated CSV files, figures, LaTeX fragments, checksums, and PDF should all correspond to the same commit.

The code change in `lib/joint_filter.ml` is substantive because it changes numerical evaluation of count likelihoods. The new large-count stability test should pass before release.

## 3. Create the software release

When the clean run passes:

1. Update any remaining references to the old paper title.
2. Commit the regenerated outputs and report.
3. Tag the commit `v1.0.0`.
4. Create a GitHub release from that tag.
5. Archive that release with Zenodo to obtain a persistent software DOI.
6. Add the final software DOI to the citation metadata after Zenodo has minted it, or reserve the DOI before release if you want it embedded in the release metadata itself.

Zenodo's official GitHub integration archives GitHub releases and assigns a DOI. `CITATION.cff` is enough for repository citation metadata. Do not add `.zenodo.json` unless you need Zenodo-specific overrides, because Zenodo gives that file precedence over `CITATION.cff` when both exist.

Official documentation:

- Zenodo GitHub integration: https://help.zenodo.org/docs/github/enable-repository/
- Zenodo DOI guidance: https://help.zenodo.org/docs/deposit/describe-records/reserve-doi/
- Citation File Format: https://citation-file-format.github.io/

## 4. Publish the report as a scholarly object

Preferred route for an EPFL student: EPFL Infoscience, subject to the rules of your section and any required supervisor approval. EPFL describes Infoscience as its institutional repository and notes that repository visibility improves discoverability in services such as Google Scholar.

If an Infoscience deposit is not available for this work, use a stable scholarly archive such as Zenodo for the report itself. Upload the final PDF as a technical report or preprint and use the exact title and author metadata from the paper.

Do not label it as peer reviewed unless it has actually completed peer review.

Official EPFL guidance:

- Infoscience help: https://www.epfl.ch/campus/library/services/infoscience/

## 5. Google Scholar

Google Scholar can index technical reports and preprints when the document is publicly accessible and has machine-readable bibliographic structure. The PDF should have the title prominently at the top of the first page, the author immediately below it, and a bibliography. A stable institutional or scholarly repository is preferable to relying on a GitHub blob URL.

For your Scholar profile:

- Name: `Mohamed Rayan Bouchaibi`
- Affiliation: `Mathematics Student, EPFL`
- Verification email: use your EPFL email address if available to you
- Areas of interest: use only fields you genuinely work in, for example `Bayesian inference`, `market microstructure`, `quantitative finance`, and `machine learning`
- Homepage: your personal academic page is preferable; your GitHub profile is acceptable if that is your only stable page

Add the report after it has a stable public record. Do not manually create a Scholar entry whose only object is the GitHub repository. Keep the software DOI in the paper's code and data availability statement and in the repository citation metadata.

Google Scholar inclusion guidance:

- https://scholar.google.com/intl/en/scholar/inclusion.html

## 6. What to claim on a CV

Before peer review, use wording such as:

`Independent technical report, Bayesian Learning and Model Risk in a Binary Market-Making Model, 2026.`

If the report receives a DOI, append the DOI. If it is later accepted by a workshop, conference, or journal, update the status at that point.

Avoid `publication` as a category label if the only public record is a self-archived report. `Research`, `Selected Projects`, or `Preprints and Technical Reports` is more precise.

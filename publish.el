(require 'package)

(setq package-archives '(("gnu"   . "http://elpa.gnu.org/packages/")
			                   ("melpa" . "https://melpa.org/packages/")
			                   ("org"   . "https://orgmode.org/elpa/")))
(package-initialize)

(unless package-archive-contents
  (package-refresh-contents))

(package-install 'htmlize)

(require 'org)
(require 'ox-publish)
(require 'htmlize)

(setq treesit-language-source-alist
      '((heex "https://github.com/phoenixframework/tree-sitter-heex.git")
        (elixir "https://github.com/elixir-lang/tree-sitter-elixir")
        (html "https://github.com/tree-sitter/tree-sitter-html")))

(dolist (lang '(elixir heex html))
  (unless (treesit-language-available-p lang)
    (treesit-install-language-grammar lang)))

;; Macros
(setq org-export-global-macros
      '(("youtube"
         . "@@html:<div class=\"youtube\">
                <iframe src=\"https://www.youtube.com/embed/$1\"
                        frameborder=\"0\"
                        allowfullscreen>
                </iframe>
              </div>@@")))

(defun my/filter-local-links (link backend info)
  "Filter that converts all the /index.html links to /"
  (if (org-export-derived-backend-p backend 'html)
	    (replace-regexp-in-string "/index.html" "/" link)))

(add-to-list 'org-export-filter-link-functions 'my/filter-local-links)

(defun my/sitemap-by-project (title list)
  "Blog sitemap grouped by project like the following:

* project-name
- entry 1
- entry 2

Then they can be included on project details page like

  #INCLUDE \"index.org::project-name\" :lines \"2-\""
  (let ((projects-alist '())
        (buffer-content "")
        (project-plist (assoc "blog" org-publish-project-alist)))
    (dolist (mixed-entry (cdr list))
      ;; We assume it can be nested only 1-level deep for co-located posts like post-name/index.org.
      (let* ((entry (if (directory-name-p (car mixed-entry))
                        (cadr (cadr mixed-entry))
                      mixed-entry))
             (file (car entry))
             (path (file-name-concat (plist-get (cdr project-plist) :base-directory) file))
             (project (my/get-project-name path)))
        (when project
          (let ((project-entries (assoc project projects-alist)))
            (if project-entries
                (setcdr project-entries (append (cdr project-entries) (list entry)))
              (push (list project entry) projects-alist))))))

    (dolist (project-group projects-alist)
      (let ((project-name (car project-group))
            (entries (cdr project-group)))
        (setq mapped-entries (mapcar (lambda (entry) (list (my/sitemap-format-entry-with-date (car entry) 'list project-plist))) entries))
        (setq buffer-content (concat buffer-content "* " project-name "\n"))
        (setq buffer-content (concat buffer-content (org-list-to-org `(unordered ,@mapped-entries))))))
    buffer-content))

(defun my/get-project-name (file)
  "Returns a file project name from the PROJECT property."
  (with-temp-buffer
    (insert-file-contents file)
    (org-mode)
    (car (cdr (assoc "PROJECT" (org-collect-keywords '("PROJECT")))))))

(defun my/sitemap-format-entry-with-date (entry style project)
  "Custom sitemap entry formatting: add date"
  (cond ((not (directory-name-p entry))
         ;; Hack so /blog links working on non-blog pages
         (format "[%s] [[file:%s][%s]]"
                 (format-time-string "%Y-%m-%d" (org-publish-find-date entry project))
                 entry
                 (org-publish-find-title entry project)))
        ((eq style 'tree)
         (file-name-nondirectory (directory-file-name entry)))
        (t entry)))

(defun my/read-template (filename)
  "Read template contents."
  (with-temp-buffer
    (insert-file-contents filename)
    (buffer-string)))

(setq head-extra-template (my/read-template "templates/head_extra.html")
      header-template (my/read-template "templates/header.html")
      footer-template (my/read-template "templates/footer.html"))

(setq shared-html-options
      `(:section-numbers nil
                         :html-head-extra ,head-extra-template
                         :html-preamble ,header-template
                         :html-postamble ,footer-template
                         :html-divs ((preamble "div" "header")
                                     (content "div" "main")
                                     (postamble "div" "footer"))
                         ;; :htmlized-source t
                         :html-doctype "html5"
                         :html-html5-fancy  t
                         :html-head-include-scripts nil
                         :html-head-include-default-style nil))

(setq org-src-fontify-natively t
      org-html-htmlize-output-type 'css
      org-html-htmlize-font-prefix "org-")

(defun my/projects-sitemap-function (title list)
  "Projects-specific simap function which appends some preamble."
  (let ((snippet (with-temp-buffer
                   (insert-file-contents "org/projects/index.inc.org")
                   (buffer-string))))
    (concat "#+TITLE: " title "\n"
            snippet
            (org-list-to-subtree list))))

(setq org-publish-project-alist
      `(("pages"
         :base-directory "org/"
         :base-extension "org"
         :publishing-directory "public/"
         :recursive nil
         :include ("contact/index.org")
         :with-toc nil
         :publish-function org-html-publish-to-html
         ,@shared-html-options)

        ;; Content
        ("projects"
         :base-directory "org/projects"
         :base-extension "org"
         :publishing-directory "public/projects"
         :recursive t
         :with-toc nil
         :exclude ".*\\.inc\\.org$"
         :auto-sitemap t
         :sitemap-title "Projects"
         :sitemap-filename "index.org"
         :sitemap-style list
         :publish-function org-html-publish-to-html
         :sitemap-function my/projects-sitemap-function
         ,@shared-html-options)

        ("blog"
         :base-directory "org/blog/"
         :base-extension "org"
         :publishing-directory "public/blog/"
         :publishing-function org-html-publish-to-html
         :recursive t
         :exclude ".*\\.inc\\.org$"
         :auto-sitemap t
         :sitemap-style list
         :sitemap-title "Blog"
         :sitemap-filename "index.org"
         :sitemap-sort-files anti-chronologically
         :sitemap-format-entry my/sitemap-format-entry-with-date
         ,@shared-html-options)

        ("projects-index"
         :base-directory "org/blog/"
         :base-extension "org"
         :publishing-directory "public/"
         :publishing-function ignore
         :auto-sitemap t
         :recursive t
         :sitemap-style list
         :sitemap-title nil
         :sitemap-filename "posts-by-project.inc.org"
         :sitemap-function my/sitemap-by-project
         :sitemap-format-entry (lambda (entry style project) entry)
         :sitemap-sort-files chronologically)

        ("static"
         :base-directory "static/"
         :base-extension "css\\|woff2"
         :recursive t
         :publishing-directory "public/static/"
         :publishing-function org-publish-attachment)

        ("assets"
         :base-directory "org/"
         :base-extension "png\\|jpg\\|jpeg"
         :recursive t
         :publishing-directory "public/"
         :publishing-function org-publish-attachment)

        ("ssbb.me" :components ("projects-index" "blog" "projects" "pages" "static" "assets"))))

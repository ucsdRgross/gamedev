// The index page (PLAN S3, chart H1–H4). Lists every design the registry found, under each
// project it touches, with its status and when it was last touched.

const body = document.getElementById('body');

/** Format an ISO timestamp as a short local date, or an em dash when there is none. */
function when(iso) {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleDateString();
}

/** One line describing whose turn it is, from the two status halves (§4.2). */
function statusLine(d) {
  if (d.owner.state === 'answering') return 'your turn — answering';
  if (d.agent.state === 'working') return 'with the agent';
  if (d.agent.state === 'ready') return `your turn — round ${d.agent.round} ready`;
  return d.owner.reason === 'new_branch_needed' ? 'with the agent — new branch needed' : 'with the agent';
}

const response = await fetch('/api/designs');
const designs = response.ok ? await response.json().catch(() => null) : null;

if (!designs) {
  // A scan that failed is not an empty repo, and saying "no designs yet" would send the owner
  // looking for a directory they never lost.
  body.innerHTML = '<p class="muted">Could not read the design index — the server answered '
    + `<span class="mono">${response.status}</span>. Its console says why.</p>`;
} else if (!designs.length) {
  body.innerHTML = '<p class="muted">No designs yet. A design is any directory with a '
    + '<span class="mono">meta.json</span> under <span class="mono">&lt;project&gt;/design/</span>.</p>';
} else {
  const byProject = new Map();
  for (const d of designs) {
    for (const p of d.projects) {
      if (!byProject.has(p)) byProject.set(p, []);
      byProject.get(p).push(d);
    }
  }
  body.replaceChildren(...[...byProject.entries()].map(([project, list]) => {
    const section = document.createElement('section');
    const h = document.createElement('h2');
    h.textContent = project;
    h.style.cssText = 'font-size:1rem;font-weight:600;margin:2rem 0 .75rem;color:var(--ink-dim)';
    const ul = document.createElement('ul');
    ul.className = 'design-list';
    for (const d of list) {
      const li = document.createElement('li');
      const a = document.createElement('a');
      a.className = 'design-card';
      a.href = `question.html?key=${encodeURIComponent(d.key)}`;
      a.innerHTML = `<div class="title"></div><div class="meta"></div>`;
      a.querySelector('.title').textContent = d.title;
      const meta = a.querySelector('.meta');
      meta.textContent = `${statusLine(d)} · ${d.answered} answered · last touched ${when(d.touched)} `;
      // Q89b=c — a gap is told in chat AND badged here. Closed ones are badged too, quietly:
      // Q96b=a keeps them with their resolutions, and a record nobody can see is not kept.
      for (const [show, className, text] of [
        [d.gaps > 0, 'gaps', `${d.gaps} open gap${d.gaps === 1 ? '' : 's'}`],
        [d.gaps_closed > 0, 'closed', `${d.gaps_closed} closed`],
      ]) {
        if (!show) continue;
        const b = document.createElement('span');
        b.className = `badge ${className}`;
        b.textContent = text;
        meta.append(' ', b);
      }
      // GAP-001=b — the document parses, so the owner is not blocked; the badge is how the
      // authoring agent finds out that one of its questions is under-specified.
      for (const [show, className, text] of [
        [d.doc_missing, 'bad', 'document missing'],
        [d.errors > 0, 'bad', `${d.errors} parse error${d.errors === 1 ? '' : 's'}`],
        [d.warnings > 0, 'warn', `${d.warnings} authoring warning${d.warnings === 1 ? '' : 's'}`],
      ]) {
        if (!show) continue;
        const b = document.createElement('span');
        b.className = `badge ${className}`;
        b.textContent = text;
        meta.append(' ', b);
      }
      if (d.archived) {
        const b = document.createElement('span');
        b.className = 'badge archived';
        b.textContent = 'archived';
        meta.append(' ', b);
      }
      // The two halves of the loop: answer the questions, or review the graph they produced.
      const links = document.createElement('div');
      links.className = 'card-links';
      const review = document.createElement('a');
      review.href = `canvas.html?key=${encodeURIComponent(d.key)}`;
      review.textContent = d.confirmed_version ? `review canvas — v${d.confirmed_version} confirmed` : 'review canvas';
      links.append(review);
      // The badge says a gap exists; this is where it is read and answered (Q90b=b — in the
      // website, because the options and their consequences read better here than in chat).
      if (d.gaps_total) {
        const gaps = document.createElement('a');
        gaps.href = `gaps.html?key=${encodeURIComponent(d.key)}`;
        gaps.textContent = d.gaps ? `answer ${d.gaps} open gap${d.gaps === 1 ? '' : 's'}` : 'gaps and their resolutions';
        links.append(' · ', gaps);
      }
      li.append(a, links);
      ul.append(li);
    }
    section.append(h, ul);
    return section;
  }));
}

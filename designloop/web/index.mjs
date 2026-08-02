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

const designs = await (await fetch('/api/designs')).json();

if (!designs.length) {
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
      if (d.gaps) {
        const b = document.createElement('span');
        b.className = 'badge gaps';
        b.textContent = `${d.gaps} open gap${d.gaps === 1 ? '' : 's'}`;
        meta.append(b);
      }
      if (d.archived) {
        const b = document.createElement('span');
        b.className = 'badge archived';
        b.textContent = 'archived';
        meta.append(' ', b);
      }
      li.append(a);
      ul.append(li);
    }
    section.append(h, ul);
    return section;
  }));
}

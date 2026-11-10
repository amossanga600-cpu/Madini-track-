# Deployment checklist (server)

1. Tengeneza Supabase project ya production na hifadhi database password.
2. Endesha `backend/schema.sql` kwenye PostgreSQL/Supabase SQL editor kama database administrator.
3. Authentication ya sasa ni FastAPI + Argon2 + JWT (si Supabase Auth). Weka `DATABASE_URL` (SSL required) na `JWT_SECRET` yenye angalau random bytes 32 kwenye secret manager ya host.
4. Deploy `backend/Dockerfile`; expose HTTPS pekee. Health checks: `/health` na `/health/ready`.
5. Unda kampuni ya kwanza: `cd backend && pip install -r requirements.txt && python bootstrap_owner.py`.
6. Unda users wa ziada kwa `POST /v1/admin/users`.
7. Weka API base URL kwenye mipangilio ya app; usiweke database credentials kwenye Flutter.
8. Fanya tests za tenant isolation, device mismatch, pull cursor, conflict resolution, restore na sync ya vifaa viwili kabla ya pilot.
9. Weka automated Postgres backups, point-in-time recovery kulingana na plan, monitoring/alerts na rate limiting ya pamoja.
10. Weka privacy policy, retention policy, incident response na utaratibu wa kufuta/kuondoa akaunti kabla ya release ya umma.

## Muhimu
Backend code imeandaliwa lakini haijaendeshwa dhidi ya Postgres halisi katika mazingira ya ujenzi. Schema, migrations na endpoints lazima zithibitishwe kwenye staging project kabla ya production. Usitumie Supabase service-role key kwenye mobile app.

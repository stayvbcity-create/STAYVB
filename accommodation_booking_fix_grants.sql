-- Fix: anon rola nema GRANT na nove accommodation_* tabele
-- (isti problem kao ranije sa authenticated — ovaj projekat ne dodaje
-- podrazumevana prava automatski na rucno kreirane tabele)

GRANT SELECT, INSERT, UPDATE ON public.accommodation_listings  TO anon;
GRANT SELECT, INSERT, UPDATE ON public.accommodation_inquiries TO anon;

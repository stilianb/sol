export interface Project {
  id: string;
  name: string;
  primary_url: string;
  competitor_urls: string[];
  status: 'draft' | 'in_progress' | 'complete';
  archived: boolean;
}

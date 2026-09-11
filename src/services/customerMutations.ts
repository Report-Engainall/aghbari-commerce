import { requireSupabase } from '../lib/supabase';
import type { CustomerTier } from '../domain/types';

const UUID_PATTERN=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export async function updateCustomer(customerId:string,name:string,phone:string,tier:CustomerTier){const id=customerId.trim();if(!UUID_PATTERN.test(id))throw new Error('معرّف العميل غير صالح.');const normalizedName=name.trim();if(!normalizedName||normalizedName.length>200)throw new Error('اسم العميل مطلوب وبحد أقصى 200 حرف.');const normalizedPhone=phone.trim();if(normalizedPhone.length>50)throw new Error('رقم هاتف العميل طويل جدًا.');const {data,error}=await requireSupabase().rpc('update_customer',{p_customer_id:id,p_name:normalizedName,p_phone:normalizedPhone||null,p_tier:tier});if(error)throw error;return data;}
